#!/opt/local/bin/perl

use PGPLOT;
use POSIX;
use DateTime::Format::ISO8601;
use Getopt::Long;
use Pod::Usage;
use List::MoreUtils qw/ uniq /;

# Parse command-line options
my $help = 0;
my $man = 0;
my $serial = 0;
my $default_color = 7;
my $title = '';
my $device = "/xs";
my $histogram = 0;
my $pulse = 0;
my $xlog = 0;
my $ylog = 0;
my $extra = 0;
my $joined = 0;
my $xformat = 0;
my $yformat = 0;
my $parabola = ();
my @polynomial = ();
my $symbol = 17;

$help = 1 if $#ARGV == -1;
$result = GetOptions(
    "color=i"=> \$default_color,
    "symbol=i"=> \$symbol,
    "xmin=f"=>\$explicit_xmin,
    "xmax=f"=>\$explicit_xmax,
    "ymin=f"=>\$explicit_ymin,
    "ymax=f"=>\$explicit_ymax,
    "skylevel=f" => \$skylevel,
    "xformat=i"=>\$xformat,
    "yformat=i"=>\$yformat,
    "png_width=i"=>\$png_width,
    "png_height=i"=>\$png_height,
    "xlog!"=>\$xlog,
    "ylog!"=>\$ylog,
    "hline=f"=> \$hline,
    "xarrow=f"=> \$xarrow,
    "hist"=> \$histogram,
    "pulse"=> \$pulse,
    "joined"=> \$joined,
    "vline=f"=> \$vline,
    "extra!"=> \$extra,
    "box=f"=> \$box,
    "covariance!"=> \$covariance,
    "device=s"=> \$device,
    "title=s"=> \$title,
    "parabola=f{3}" => \@parabola,
    "gaussian=f{3}" => \@gaussian,
    "polynomial=f{,}" => \@polynomial,
    "serial" => \$serial, 
    "help|?" => \$help, 
     man=> \$man) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

$ENV{PGPLOT_PNG_WIDTH} = $png_width if defined($png_width);
$ENV{PGPLOT_PNG_HEIGHT} = $png_height if defined($png_height);

# Load the column/filter to plot
my $keyX  = $ARGV[0];
my $keyY  = $ARGV[1];

$has_errorbars = 0;
if ($#ARGV==2) {
    $keySigma = $ARGV[2];
    $has_errorbars = 1;
}

die "Error: DATE must be on the X-axis; stopped" if $keyY =~ /^DATE/;
die "Error: DATE must be on the X-axis; stopped" if $keySigma =~ /^DATE/;

# Load the data table
my $xmax = -1e100;
my $xmin =  1e100;
my $ymax = -1e100;
my $ymin =  1e100;
my $colnum=0;
my $count=0;
my @serial_numbers = ();

while(<STDIN>)
{
    my $line = $_;
    if ($line =~ /^#/) {

        next if $line =~ /^$\!/;

        @fields = split;
        $keyword = $fields[2];

        # Define column numbers to correspond to SExtractor keywords
        # so for example: $col{"FLUX_ISO"}=3 etc.
        $col{$keyword}=$colnum++;

        next;
    }
    chomp($line);
    $line =~ s/^\s+//;
    @column = split(' ',$line);

    $x[$count] = $column[$col{$keyX}];
    $x[$count] = log($x[$count])/log(10) if ($xlog);
    $xmin = $x[$count] if ($x[$count] !~ /n/ && $x[$count] < $xmin);
    $xmax = $x[$count] if ($x[$count] > $xmax);

    $y[$count] = $column[$col{$keyY}];
    $y[$count] -= $skylevel if $skylevel;
    if ($ylog){
        next if ($y[$count] <= 0);
        $y[$count] = log($y[$count])/log(10);
    }
    $ymin = $y[$count] if ($y[$count] !~ /n/ && $y[$count] < $ymin);
    $ymax = $y[$count] if ($y[$count] > $ymax);

    if ($has_errorbars) {
        $sigma[$count] = $column[$col{$keySigma}];
        $ylo[$count] = $y[$count] - $sigma[$count];
        $yhi[$count] = $y[$count] + $sigma[$count];
    }

    if ($serial) {
        $sn[$count] =  $column[$col{"SERIAL_NUMBER"}];
    }

    # Assign the default plot color to each data point
    $color[$count] = $default_color;

    $count++;
}

# Expand the plot window a tiny bit... it looks better that way
$xmin = $xmin - 0.05*abs($xmax - $xmin);
$xmax = $xmax + 0.05*abs($xmax - $xmin);
$ymin = $ymin - 0.05*abs($ymax - $ymin);
$ymax = $ymax + 0.05*abs($ymax - $ymin);

# Manual overrides
$xmin = $explicit_xmin if defined($explicit_xmin);
$xmax = $explicit_xmax if defined($explicit_xmax);
$ymin = $explicit_ymin if defined($explicit_ymin);
$ymax = $explicit_ymax if defined($explicit_ymax);

# Assign different colors to different serial numbers
if ($serial) {
    @palette = (7,4,2,3,5,7,4,2,3,5);
    my @serial_number = uniq @sn;
    for ($i=0;$i<$count;$i++) {
        $color_count = 0;
        foreach(@serial_number) {
            if ($sn[$i] =~ /$_/) {
                $color[$i] = $palette[$color_count];
            }
            $color_count++;
        }
    }
}


if ($keyX =~ /^DATE/) {

    # Work out the UTC offset in a way that will work even for Daylight Savings time
    $now = DateTime->now;
    $now->set_time_zone('America/Montreal');
    $now_utc = $now->clone();
    $now_utc->set_time_zone('UTC');
    $UTC_offset_hours  = $now_utc->hour() - $now->hour();
    $UTC_offset_hours = 24 - abs($UTC_offset_hours) if ($now_utc->day() != $now->day());

    @time = @x  if ($keyX =~ /^DATE/);
    @time = @y  if ($keyY =~ /^DATE/);

    $count = 0;
    foreach(@time) {
        $dt[$count] = DateTime::Format::ISO8601->parse_datetime($_);
        $dt[$count]->set_time_zone('UTC');
        $jd[$count] = $dt[$count]->mjd();
        $count++;
    }

    # In order to display sexagesimal times nicely, pgplot requires the window 
    # be defined with time in seconds. This time has to be an offset though
    # because pgplot uses single precision internally and the julian date
    # of the data is large, so information after the decimal place can get
    # lost (see the description of pgtbox in the manual). We also want to
    # account for the fact that the data is retreived in UTC but we want to
    # plot local time.
    $start_day = int($jd[$count-1]);
    for($i=0;$i<$count;$i++) {
        $js[$i] = 86400.0*($jd[$i]-$start_day) - 3600*$UTC_offset_hours;

        # The next line is a kludge to account for the possibility that the 
        # time stream does not have enough datapoints to span a single day, in
        # which case the UTC_offset_hours correction above may oversubtract.
        $js[$i] += 86400 if ($js[$count]<=0);
    }

    @x = @js;
    $xmin = $js[0];
    $xmax = $js[$count-1];
}


pgbegin(0,$device,1,1);  # /CGW, /XW, /XS, /PNG, /PS ETC
pgsch(1.0);
pgswin($xmin,$xmax,$ymin,$ymax);
if ($keyX =~ /^DATE/) {
    pgtbox('ZYXHOBCTNMSV',0.0,0,'BCNMST',0.0,0);
}
else {
    pgbox('BCNMST'.$xformat,0.0,0,'BCNMST'.$yformat,0.0,0);
}

# Graphical sugar gets drawn first so the data is on top of it.

if (defined($hline)){
    pgsci(6);
    pgline(2,[$xmin,$xmax],[$hline,$hline]);
}
if (defined($vline)){
    pgsci(6);
    pgline(2,[$vline,$vline],[$ymin,$ymax]);
}
if (defined($box)){
    pgsci(4); # blue
    pgline(5,[-$box/2,$box/2,$box/2,-$box/2,-$box/2],[-$box/2,-$box/2,$box/2,$box/2,-$box/2]);
    pgslw(1);
}
if (@parabola>0){
    for ($i=0;$i<$count;$i++) {
        $yp[$i] = $parabola[0] + $parabola[1]*$x[$i] + $parabola[2]*($x[$i]**2);
    }
    pgsci(4); # blue
    pgsls(4); # dotted
    pgline($count,*x,*yp);
}
if (@gaussian>0){
    $nx = 200;
    $dx = ($xmax - $xmin)/$nx;
    for ($i=0;$i<$nx;$i++) {
        $xg[$i] = $xmin + $i*$dx;
        $yg[$i] = $gaussian[0] * exp(-0.5*(($xg[$i] - $gaussian[1])/$gaussian[2])**2);
    }
    pgsci(4); # blue
    pgsls(4); # dotted
    pgline($nx,*xg,*yg);
}
if (@polynomial>0){
    $nx = 200;
    $dx = ($xmax - $xmin)/$nx;
    $order = @polynomial;
    for ($i=0;$i<$nx;$i++) {
        $xc[$i] = $xmin + $i*$dx;
        $yc[$i] = 0.0;
        for ($j=0;$j<$order;$j++) {
            $yc[$i] += $polynomial[$j]*pow($xc[$i],$j);
        }
    }
    pgsci(4); # blue
    pgsls(4); # dotted
    pgline($nx,*xc,*yc);
}

if ($xarrow) {
    pgsci(2);
    pgarro($xarrow,$ymin+($ymax-$ymin)/3,$xarrow,$ymin+($ymax-$ymin)/6);
}

# Data
pgsci(1);
pglabel($keyX,$keyY,$title);
pgsci(7);
pgsch(1.5);
if (!$histogram){
    for ($i=0;$i<$count;$i++) {
        if ($extra) {
            printf(STDERR "%f %f\n",$x[$i],$sigma[$i]);
            pgsci(4);
            pgsch(1.0);
            pgpoint(1,$x[$i],$sigma[$i],$symbol);
        }
        elsif ($has_errorbars) {
            pgerry(1,$x[$i],$ylo[$i],$yhi[$i],0.0) if $has_errorbars;
        }
        pgsch(1.5);
        pgsci($color[$i]);
        pgsls(1);
        pgpoint(1,$x[$i],$y[$i],$symbol);
        pgline($count,*x,*y) if ($joined);
        pgline(2,[$x[$i],$x[$i]],[0.0,$y[$i]]) if $pulse;
    }
}
else {
    pgbin($count,*x,*y,1);
}

# Drawing the covariance ellipse
#
# See http://mathworld.wolfram.com/CorrelationCoefficient.html
# for descriptions of the definitions.

if (defined($covariance)) {

    # Mean values
    $mx = 0;
    $my = 0;
    for ($i=0;$i<$count;$i++) {
        $mx += $x[$i];
        $my += $y[$i];
    }
    $mx /= $count;
    $my /= $count;

    # Correlation coefficients (un-normalized second moments)
    $sxx = 0;
    $sxy = 0;
    $syy = 0;
    for ($i=0;$i<$count;$i++) {
        $sxx += ($x[$i]-$mx)*($x[$i]-$mx);
        $syy += ($y[$i]-$my)*($y[$i]-$my);
        $sxy += ($x[$i]-$mx)*($y[$i]-$my);
    }

    # Variances and covariances (normalized correlation coefficients)
    $vx  = $sxx/$count;
    $vy  = $syy/$count;
    $cov = $sxy/$count;

    # The covariance matrix is:
    #  [vx  cov]
    #  [cov  vy] 
    #
    #  If T is the trace and D is the determinant, the eigenvalues are:
    #
    #  L1 = T/2 + ((T**2)/4-D)**(1/2)
    #  L2 = T/2 - ((T**2)/4-D)**(1/2)
    
    $T = ($vx + $vy);
    $D = ($vx * $vy - $cov * cov);
    $L1 = $T/2.0 + (($T**2)/4.0-$D)**0.5;
    $L2 = $T/2.0 - (($T**2)/4.0-$D)**0.5;

    printf("2.35*sqrt(L1) = %5.2f    2.35*sqrt(L2) = %5.2f\n",2.35 * sqrt($L1),2.35 * sqrt($L2));
    printf("in arcsec     = %5.2f    in arcsec     = %5.2f\n",18.5*2.35 * sqrt($L1),18.5*2.35 * sqrt($L2));
 
}



pgend;


__END__

=head1 NAME

tplot - Plot data from a SExtractor format data table (including timestreams)

=head1 SYNOPSIS

tplot [options] xaxis yaxis < summary.txt

=head1 ARGUMENTS

=over 8

=item B<xaxis>

Column name for the X-axis.

=item B<yaxis>

Column name for the Y-axis.

=back

=head1 OPTIONS

=over 8

=item B<--xmin number>

Minimum X-value to plot.

=item B<--xmax number>

Maximum X-value to plot.

=item B<--ymin number>

Minimum Y-value to plot.

=item B<--ymax number>

Maximum Y-value to plot.

=item B<--serial>

Use color to distinguish between points with different values in the
SERIAL_NUMBER column.

=item B<--color number>

Color to use for plot symbols. The palette is:
0 = WHITE, 1 = BLACK, 2 = RED, 3 = GREEN, 4 = BLUE,
5 = CYAN, 6 = MAGENTA, 7 = YELLOW, 8 = ORANGE, 14 = DARKGRAY,
16 = LIGHTGRAY

=item B<--hline number>

Draw a horizontal line at Y=number

=item B<--vline number>

Draw a vertical line at X=number

=item B<--box number>

Draw a box with full-width number centered at (0,0).

=item B<--polynomial number1 [number2] [number3] ... [numberN]>

Draw a polynomial with coefficints specified by the arguments. The order of the
polynomial is specified by the number of arguments - 1. (So 1 argument = 0th order, i.e. a 
constant; 2 arguments = 1st order, i.e. a line; 3 arguments = 2nd order, i.e. a parabola; 
4 arguments = 3rd order, i.e. a cubic, etc.)

=item B<--xformat [1|2]>

Controls whether the X axis is labeled in decimal or exponential format.  1:
force decimal labelling, instead of automatic choice.  2: force exponential
labelling, instead of automatic.

=item B<--yformat [1|2]>

Controls whether the Y axis is labeled in decimal or exponential format.  1:
force decimal labelling, instead of automatic choice.  2: force exponential
labelling, instead of automatic.

=item B<--hist>

Draw using a histogram style.

=item B<--joined>

Plot points joined by lines

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.


=back

=head1 DESCRIPTION

B<tplot> plots the two columns of a SExtractor-format ASCII data table against
each other. The X-axis data values can be numeric or an ISO-standard date+time 
string. If a date+time string is used Universal Time is assumed and the data
is converted to local time before being plotted.

=head1 EXAMPLES 

summarize *.fits > foo.txt
tplot DATE MEAN <foo.txt 

extract foo.fits > foo.txt
tplot X_IMAGE Y_IMAGE <foo.txt

=cut
