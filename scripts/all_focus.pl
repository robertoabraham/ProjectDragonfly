#!/opt/local/bin/perl

use Getopt::Long;
use Pod::Usage;
use DateTime;

# Set up the interrupt handling
$exit_asap = 0;
$SIG{'INT' } = 'interrupt';  $SIG{'QUIT'} = 'interrupt';
$SIG{'HUP' } = 'interrupt';  $SIG{'TRAP'} = 'interrupt';
$SIG{'ABRT'} = 'interrupt';  $SIG{'STOP'} = 'interrupt';

# Parse command-line options
my $verbose = 0;
my $simple = 0;
my $help = 0;
my $man = 0;
my $force = 0;
my $mail = 1;
$result = GetOptions(
    "verbose!" => \$verbose,
    "force!" => \$force,
    "mail!" => \$mail,
    "help|?" => \$help,
    "simple!" => \$simple,
     man=> \$man) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

# Startup options
$| = 1;
$focused_at_least_once_flag_file = "FOCUS_RUN_COMPLETED.txt";
$focus_positions_file = "LATEST_FOCUS_POSITIONS.txt";

if ($ARGV[0]) {
    $resolution = $ARGV[0];
}
else {
    $resolution = "fine";
}

# Define option strings for options that need to propagate to focus.pl
if ($force)   {$forcestring = " --force "} else {$forcestring = " --noforce "};
if ($mail)    {$mailstring = " --mail "} else {$mailstring = " --nomail "};
if ($simple)  {$simplestring = " --simple "} else {$simplestring = " --nosimple "};

# Don't do a focus run if it's time for morning flats
chomp($action = `almanac | grep SuggestedAction | awk '{print \$2}'`);
if ($action =~ /MorningFlat/) {
    `syslog -s -l alert [DragonflyStatus] Not focusing because the time for morning flats has arrived.`; 
    die "Not focusing because it's time for morning flats\n";
}

$start_time = DateTime->now();
$log_message = "[DragonflyStatus] all_focus begun - resolution: $resolution.";
`syslog -s -l alert $log_message`;

# Don't do a focus run if the roof is closed.  If for some reason the status of the
# roof is unknown wait a few seconds and try again. In the event it is still
# unknown, then assume it is open.
#
# Don't do a focus run if sky conditions are poor. We check the all-sky image
# and if for some reason this check fails we wait 5s and try again. In the
# event we still can't tell the sky conditions, assume they're OK.
if (!$force) {
   print "Determining position of the observatory roof.\n" if $verbose;
    $roof = `nms_roof_status`;
    if ($roof =~ /Unknown/){
        sleep 5;
        $roof = `nms_roof_status`; 
    }
    $roof = "Open" if ($roof =~ /Unknown/);  
    $log_message = "[DragonflyStatus] Roof status: $roof";
    `syslog -s -l alert $log_message`;
    die "    Roof is closed. Cannot focus.\n" if ($roof =~ /Closed/);

   print "Determining sky conditions from the all-sky image.\n" if $verbose;
    $skyqual = `nms_sky_conditions`;
    if ($?){
        sleep 5;
        $skyqual = `nms_sky_conditions`;
    }
    chomp($skyqual);
    $log_message = "[DragonflyStatus] Sky conditions: $skyqual";
    `syslog -s -l alert $log_message`;
    die "  Conditions poor: $skyqual. Focusing aborted\n" if ($skyqual =~ /Daytime|Moonlight|Cloudy/);

    # If this is the first focus run of the night force it to do a coarse focus first, and
    # set the solution to be the minimum.
    unless ($resolution =~ /coarse/ || -e $focused_at_least_once_flag_file) {
        print "*********************************************************\n";
        print "    The FOCUS_RUN_COMPLETED.txt file doesn't exist so    \n";
        print "    an initial coarse focus run will be done first.      \n";
        print "*********************************************************\n";
        `all_focus --simple coarse`;
    }
}

# Determine the IP addresses of the computers hosting cameras
$ip=`camera_info host lens location status | grep NewMexicoSkies | grep Nominal | awk '{print \$2}' | sort | uniq | tr '\n' ' '`;
@ip = split('\s+',$ip);

# Do it baby!
`df_send cameras "focus $forcestring $mailstring $simplestring $resolution"`;

# Check that autofocusing has completed
print "Monitoring focus runs on these machines: @ip\n" if $verbose;
foreach(@ip) {
    print "Checking CCD status to determine whether autofocusing is completed.\n" if $verbose;
    $result="Autofocus";
    while($result =~ /Autofocus/){
        $result=`send $_ 7078 status`;
        sleep(1);
    }
    print "Mac Mini at IP address $_ reports that autofocusing has completed.\n" if $verbose;
}

# Store the final focus values in a text file
$results=`df_send focuser status`;
open(RESULTS,">$focus_positions_file");
print RESULTS $results;
close(RESULTS);

# How many lenses have been blessed as being in good focus?
$focus_time += timing($start_time);
chomp($ngood=`df_send focusers status | grep Blessed:True | wc | awk '{print \$1}'`);
$log_message = "[DragonflyStatus] all_focus completed in $focus_time sec. Number of lenses in decent focus: $ngood";
`syslog -s -l alert $log_message`;

# If at least 5 cameras are in focus then we declare victory and create a dummy
# file which indicates that a focus run has been successfully completed.
# Otherwise we zap the file and declare that the setup is currently out of focus.
# We execute a focus initialization step so the next time it starts from square
# one.
if ($ngood>=5) {
    `touch $focused_at_least_once_flag_file`;
}
else {
    `rm -f $focused_at_least_once_flag_file`;
    print "Less than 5 cameras are in good focus. Re-initializing all focusers.\n" if $verbose;
    $log_message = "[DragonflyStatus] all_focus is re-initializing the focusers";
    `syslog -s -l alert $log_message`;
    `all_initfocus`;
}


exit(0);



sub interrupt {
     my($signal)=@_;
     print "Caught Interrupt\: $signal \n";
     `df_send cameras "abort"`;
     exit(1);
}



sub timing {
    my $start_time = shift;
    my $end_time = DateTime->now();
    my $elapsed_time = ($end_time->subtract_datetime_absolute($start_time))->in_units('seconds');
    return($elapsed_time);
}


__END__

=head1 NAME

all_focus - Focus all lenses in a dragonfly array

=head1 SYNOPSIS

all_focus [options] [resolution]

options:

 --verbose
 --help
 --man

=head1 ARGUMENTS

=over 8

=item B<[resolution]>

One of "coarse", "fine" or "superfine". Default is "fine";

=back

=head1 OPTIONS

=over 8

=item B<--[no]simple>

Define focus by position of lowest FWHM rather than by fitting a parabola to FWHM vs position. Default is --nosimple.

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<all_focus> focuses all cameras in a Dragonfly array. A successful focus run creates
a file named 'FOCUS_RUN_COMPLETED.txt' in the directory from which all_focus is run.
If this file doesn't exist then all_focus first does a coarse focus run before attempting
to run at a finer resolution. If, after attempting a non-coarse focus, less than 5 cameras
are still not in focus, then the focusers are re-initialized to their default values.

=cut
