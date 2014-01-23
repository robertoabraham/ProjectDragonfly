#!/opt/local/bin/perl

use Getopt::Long;
use Pod::Usage;
use File::Basename;
use DateTime;
use DateTime::Format::ISO8601;
use DateTime::Format::Duration;


# Set up the interrupt handling
$exit_asap = 0;
$SIG{'INT' } = 'interrupt';  $SIG{'QUIT'} = 'interrupt';
$SIG{'HUP' } = 'interrupt';  $SIG{'TRAP'} = 'interrupt';
$SIG{'ABRT'} = 'interrupt';  $SIG{'STOP'} = 'interrupt';

# Parse command-line options
my $angle = 10.0;           # dither angle in arcmin
my $nwanted = 8;
my $host = "XXX.XXX.XXX.XXX";
my $port = 3040;
my $reg = "[1000:1500,900:1200]";
my $verbose = 1;
my $simulate = 0;
my $min_counts = 5000;
my $max_counts = 15000;
my $max_exptime = 60;
my $man = 0;
my $help = 0;

$result = GetOptions(
    "angle=f" => \$angle,
    "nwanted=i" => \$nwanted,
    "reg=s" => \$reg,
    "host=s" => \$host,
    "port=i" => \$port,
    "simulate!" => \$simulate,
    "verbose" => \$verbose,
    "help|?" => \$help, 
     man=> \$man) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;
pod2usage(2) if $narg != 0;

# Startup options
$| = 1;

# If the INTERRUPT.txt file exists, bail out. This gives the user a chance to bail out without sending a ^C.
# This doesn't delete the INTERRUPT.txt file so the next auto_observe will not happen either.
if (-e "INTERRUPT.txt"){
    `syslog -s -l alert [DragonflyStatus] auto_morning_flats aborted - INTERRUPT.txt file found.`;
    die "Exiting auto_morning_flats because the INTERRUPT.txt has been found.";
}

# Bail out if the almanac says we're supposed to be parked because the sky is way too bright.
if ($action =~ /Park/) {
    `syslog -s -l alert [DragonflyStatus] auto_morning_flats: aborting because the almanac says the sky is too bright.`;
    die "It is too bright for flats.";
}

# If needed, kill time until the almanac program says it is time for flats
chomp($action = `almanac | grep SuggestedAction | awk '{print \$2}'`);
while ($action =~ /Observe/) {
    `syslog -s -l alert [DragonflyStatus] auto_morning_flats: almanac says the time for morning flats has not arrived. Sleeping for 5 mins.`;
    sleep(300);
    chomp($action = `almanac | grep SuggestedAction | awk '{print \$2}'`);
}

# At this point the only sensible option is that we should be doing a morning flat. Verify we are indeed in this state.
if ($action !~ /MorningFlat/) {
    `syslog -s -l alert [DragonflyStatus] auto_morning_flats: unknown error. State = $action.`;
    die "Unknown error.";
}

# OK, looks like we have a green light to go for morning flats. Proceed!
chomp($tonightdir=`df_send cameras pwd | head -1 | awk '{print \$4}' | sed 's/\\/Users\\/dragonfly\\/Data\\///g'`);
print "Data being stored in: $tonightdir\n";

# Time stamp
$start = `date`;
print "Starting flats at $start" if $verbose;
`syslog -s -l alert [DragonflyStatus] auto_morning_flats begun. Data will be stored in $tonightdir.`;
`mutt -s "Morning flats begun." projectdragonfly\@icloud.com < /dev/null`; 

# Slew to the best place for flats
$flat_alt = 70.0;
$flat_az = 110.0;
print "Slewing to pre-defined flat field location (Alt=$flat_alt Az=$flat_az)\n" if $verbose;
`mount --host $host altaz $flat_alt $flat_az`;

# We're good to go... try to take the data
$ngood = 0;
$ntries = 0;
$nmaxtries = 25;
$exptime = 30;
$firstpass = 1;
@exptimes = ();
while($ngood < $nwanted) {

    print "Determining position of the observatory roof.\n" if $verbose;
    $roof = `nms_roof_status`;
    if ($roof =~ /Closed/ && !$simulate){    
        `syslog -s -l alert [DragonflyStatus] auto_morning_flats - Roof is closed. Obtained $ngood flats. Exiting.`;
        die "Roof is closed - no morning flats possible.";
    }

    print "  Integrating for $exptime second(s)\n" if $verbose;
    `syslog -s -l alert [DragonflyStatus] auto_morning_flats - Integrating for $exptime seconds.`;
    $start_time = DateTime->now();
    `all_expose --name "twilight_flat" flat $exptime`; 
    sleep(1);

    # Determine count rate
    $stats = `df_send cameras statistics`;
    @stats = split /\n/, $stats;
    foreach my $line (@stats) {
        ($dummy, $file)  = split( '=', $line) if ($line =~ /^File/);
        ($dummy, $counts)  = split( '=', $line) if ($line =~ /^Mean/);
    }

    $file =~ /(^.+)_(.+)_(.+)/;
    $serial_number = $1;
    $serial_number =~ s/^\.\///g; # nuke preceding ./
    $file_number = $2;
    print "Camera is: $serial_number\n";
    print "File number is: $file_number\n";

    $bias = `camera_info bias | grep $serial_number | awk '{print \$2}'`;
    chop($bias);
    $counts = $counts - $bias;
    $counts = 10 if ($counts<=0);  # Sometimes we're a bit negative if it's very dark.

    # Keep or delete the files here depending on what we just found for the single CCD frame
    if ($counts < $min_counts || $counts > $max_counts){
        # discard
        `syslog -s -l alert [DragonflyStatus] auto_morning_flats - Integration has $counts counts. Discarding it.`;
        printf("Bias-subtracted counts = %d (Too low - discarding these files)\n",int($counts)) if $counts < $min_counts;
        printf("Bias-subtracted counts = %d (Too high - discarding these files)\n",int($counts)) if $counts > $max_counts;
        $zapme = "*_" . $file_number . "_flat.fits";
        $command = "df_send cameras \"rm $zapme\"";
        print "Removing file(s) with command: $command\n" if $verbose;
        `$command`; 
    }
    else {
        # keep the file and store the integration time in an array so we can get darks of
        # the same duration later.
        `syslog -s -l alert [DragonflyStatus] auto_morning_flats - Integration has $counts counts. Keeping it.`;
        printf("Bias-subtracted counts = %d (Looks good - keeping these files)\n",int($counts));
        $ngood++;
        unshift(@exptimes,$exptime);

        # dither
        $dither_command = "mount dither $angle N";
        print "  Dither command issued: $dither_command\n" if $verbose; 
        `$dither_command`;
    }

    # Determine next exposure time using the approximation that the integration time doubles (halves) every
    # three minutes in the evening (morning), according to Tyson & Gal (1993).
    $target_adu = 0.5*($max_counts + $min_counts);
    print "Target ADU is: $target_adu\n";

    $end_time = DateTime->now();
    $elapsed_time = ($end_time->subtract_datetime_absolute($start_time))->in_units('seconds');

    print "Time difference is $elapsed_time seconds.\n";
    $exptime = int($exptime*($target_adu/$counts)/(2.0 ** ($elapsed_time/180.0))+0.5); # round up to the nearest second
    print "Suggested exposure time: $exptime\n" if ($exptime>0);
    print "Suggested exposure is less than 1s\n" if ($exptime==0);
    `syslog -s -l alert [DragonflyStatus] auto_morning_flats - Next integration time will be $exptime second(s).`;
 
    # Should we continue? Do two tests.
    
    # Test 1: is the exposure time unreasonable?
    if ($exptime <= 1) {
        print "Exposure time is too short. Flat fielding is over.\n";
        `syslog -s -l alert [DragonflyStatus] auto_morning_flats: Exposure time too short. Exiting.`;
        last;
    }

    if ($exptime > $max_exptime) {
        print "Exposure time is too long. Wait 5 mins and try again.\n";
        `syslog -s -l alert [DragonflyStatus] auto_morning_flats: Exposure time too long. Pausing for 5 min and trying with $max_exptime s.`;
        sleep(300);
        $exptime = $max_exptime;
    }

    # Test 2: does the almanac program say to bail out?
    chomp($action = `almanac | grep SuggestedAction | awk '{print \$2}'`);
    if ($action !~/Flat/) {
        `syslog -s -l alert [DragonflyStatus] auto_morning_flats - Almanac says flat fielding is over. Exiting.`;
        print "Flat fielding is over because the almanac says so!\n";
        last;
    }

    # If the user hits ^C try to bail out somewhat gracefully
    die "Exiting due to manual interrupt.\n" if $exit_asap;

} 

# Obtain darks at the end
print "\nObtaining dark frames\n" if $verbose;
foreach $exptime (uniq(@exptimes)) {
    print "  Obtaining a dark with integration time $exptime second(s)\n";
    `all_expose dark $exptime` if !$simulate;
    if ($simulate) {
        print "  Faking a dark exposure with integration time $exptime\n";
        sleep(int($exptime));
    }
}

$end = `date`;
print "Finished taking flats at $end" if $verbose;
`syslog -s -l alert [DragonflyStatus] auto_morning_flats - Sequence ended. Obtained $ngood flats.`;
`email_all_sky_image -s "Finished taking morning flats. Obtained $ngood pointings." --altaz $flat_alt $flat_az`;
#`mutt -s "Finished taking morning flats. Obtained $ngood pointings." projectdragonfly\@icloud.com < /dev/null`; 

sub interrupt {
     my($signal)=@_;
     print "Caught Interrupt\: $signal \n";
     print "The program will exit cleanly after the next integration is completed.\n";
     $exit_asap = 1;
}


sub uniq {
    my %seen = ();
    my @r = ();
    foreach my $a (@_) {
        unless ($seen{$a}) {
            push @r, $a;
            $seen{$a} = 1;
        }
    }
    return @r;
}

__END__

=head1 NAME

auto_morning_flats - Obtain morning twilight flat fields

=head1 SYNOPSIS

auto_flats

options:

 --nwanted integer
 --angle arcmin
 --verbose
 --help
 --man

=head1 OPTIONS

=over 8

=item B<--nwanted integer>

Number of flat fields wanted. Default is 6.

=item B<---angle arcmin>

Dither angle in arcminutes between each flat field integration (default is 10)

=item B<--verbose>

Print extra help information.

=item B<---help>

Prints a brief help message and exits.

=item B<---man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<auto_morning_flats> slews to a pre-defined altitude/azimuth and attempts to obtain a
series of evening twilight flats. It uses the Tyson & Gal algorithm to
determine the optimal integration times. 

=cut
