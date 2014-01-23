#!/opt/local/bin/perl

use PGPLOT;
use POSIX;
use DateTime::Format::ISO8601;
use Getopt::Long;
use Pod::Usage;
use List::MoreUtils qw/ uniq /;
use File::Basename;

# Parse command-line options
my $help = 0;
my $man = 0;
my $default_color = 7;
my $title = '';
my $device = "/xs";
my $joined = 0;
my $xformat = 0;
my $yformat = 0;

$help = 1 if $#ARGV == -1;
$result = GetOptions(
    "color=i"=> \$default_color,
    "xmin=f"=>\$explicit_xmin,
    "xmax=f"=>\$explicit_xmax,
    "ymin=f"=>\$explicit_ymin,
    "ymax=f"=>\$explicit_ymax,
    "xformat=i"=>\$xformat,
    "yformat=i"=>\$yformat,
    "hline=f"=> \$hline,
    "joined"=> \$joined,
    "vline=f"=> \$vline,
    "device=s"=> \$device,
    "title=s"=> \$title,
    "help|?" => \$help, 
     man=> \$man) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

# Load the column/filter to plot
my $keyX = $ARGV[0];
my $keyY = $ARGV[1];

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

    # Include only non-bad data points
    if ($column[$col{$keyY}] > 0.0 && $column[$col{"FILENAME"}] =~ /light/) {

        $file[$count] = $column[$col{"FILENAME"}];
        $file[$count] = basename($file[$count]);
        $cam[$count] = $column[$col{"SERIAL_NUMBER"}];

        $x[$count] = $column[$col{$keyX}];
        $xmin = $x[$count] if ($x[$count] !~ /n/ && $x[$count] < $xmin);
        $xmax = $x[$count] if ($x[$count] > $xmax);

        $y[$count] = $column[$col{$keyY}];
        $ymin = $y[$count] if ($y[$count] !~ /n/ && $y[$count] < $ymin);
        $ymax = $y[$count] if ($y[$count] > $ymax);

        if ($has_errorbars) {
            $sigma[$count] = $column[$col{$keySigma}];
            $ylo[$count] = $y[$count] - $sigma[$count];
            $yhi[$count] = $y[$count] + $sigma[$count];
        }

        $sn[$count] =  $column[$col{"SERIAL_NUMBER"}];

        # Assign the default plot color to each data point
        $color[$count] = $default_color;

        $count++;
    }
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

# Assign different colors to different filter names
$palette{"(WhiteLight)"} = 1;
$palette{"(SloanG)"} = 3;
$palette{"(SloanR)"} = 2;

# Assign colors to the camera serial numbers 
my @serial_number = uniq @sn;
foreach(@serial_number) {
    $filter_name = `camera_info filters location | grep NewMexicoSkies | grep $_ | awk '{print \$2}'`;
    chop($filter_name);
    $color{$_} = $palette{$filter_name};
}

# Assign colors to the data points
for ($i=0;$i<$count;$i++) {
    $color[$i] = $color{$sn[$i]};
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
pglabel($keyX,$keyY,$title);

# Define the plot symbol scheme 
$cross = 5;
$triangle = 7;
$dot = 17;
$star = 12;
$symb{"83F010827"} = $dot;
$symb{"83F010783"} = $dot;
$symb{"83F010820"} = $cross;
$symb{"83F010687"} = $cross;
$symb{"83F010730"} = $dot;
$symb{"83F010784"} = $star;
$symb{"83F010692"} = $cross;
$symb{"83F010826"} = $triangle;

# Draw the graphical sugar first so the data is on top of it
if (defined($hline)){
    pgsci(6);
    pgline(2,[$xmin,$xmax],[$hline,$hline]);
}
if (defined($vline)){
    pgsci(6);
    pgline(2,[$vline,$vline],[$ymin,$ymax]);
}

# Draw the data points
pgsci(7);
pgsch(1.5);
for ($i=0;$i<$count;$i++) {
    pgsci($color[$i]);
    pgpoint(1,$x[$i],$y[$i],$symb{$cam[$i]});
    pgerry(1,$x[$i],$ylo[$i],$yhi[$i],0.0) if $has_errorbars;
}

# Label the lenses outside the plot area
$disp[0] = 2.5; $coord[0] = 0.00;
$disp[1] = 3.7; $coord[1] = 0.00;
$disp[2] = 2.5; $coord[2] = 0.25;
$disp[3] = 3.7; $coord[3] = 0.25;
$disp[4] = 2.5; $coord[4] = 0.50;
$disp[5] = 3.7; $coord[5] = 0.50;
$disp[6] = 2.5; $coord[6] = 0.75;
$disp[7] = 3.7; $coord[7] = 0.75;
my @serial_number = uniq @sn;
$scount = 0;
foreach(@serial_number) {
    $snum = "$_"; 
    #print "$snum\n";
    pgsci($color{$snum});
    pgsch(0.85);
    $snum = $snum . " (\\m$symb{$snum})";
    pgmtxt('T',$disp[$scount],$coord[$scount],0.0,$snum);
    $scount++;
}

# Smart joining of datasets defined by serial number
if ($joined) {
    my @serial_number = uniq @sn;
    foreach(@serial_number) {
        $snum = $_;
        my @xline;
        my @yline;
        my $npts = 0;
        for ($i=0;$i<$count;$i++) {
            if ($sn[$i] =~ $snum) {
                $xline[$npts] = $x[$i];
                $yline[$npts] = $y[$i];
                $color = $color[$i];
                $npts++;
            }
        }
        pgsci($color);
        pgline($npts,\@xline,\@yline);
    }
}

# Label some key points with file numbers
pgsci(7);
my @serial_number = uniq @sn;
foreach(@serial_number) {
    $snum = $_;
    for ($i=0;$i<$count;$i++) {
        #print "$sn[$i] <-> $snum\n";
        if ($sn[$i] =~ $snum) {
            if ($snum =~ /83F010730/){
                $lbl = $file[$i];
                $lbl =~ /(.*)_(.*)_(.*)/;
                $lbl = $2;
                pgtext($x[$i],$y[$i],$lbl);
            }
        }
    }
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

=item B<--xformat [1|2]>

Controls whether the X axis is labeled in decimal or exponential format.  1:
force decimal labelling, instead of automatic choice.  2: force exponential
labelling, instead of automatic.

=item B<--yformat [1|2]>

Controls whether the Y axis is labeled in decimal or exponential format.  1:
force decimal labelling, instead of automatic choice.  2: force exponential
labelling, instead of automatic.

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
