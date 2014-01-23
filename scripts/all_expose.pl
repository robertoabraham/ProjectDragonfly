#!/opt/local/bin/perl

use Getopt::Long;
use Pod::Usage;
use Term::ProgressBar;
use DateTime;

# Do not buffer output
$| = 1;

# Set up the interrupt handling
$SIG{'INT' } = 'interrupt';  $SIG{'QUIT'} = 'interrupt';
$SIG{'HUP' } = 'interrupt';  $SIG{'TRAP'} = 'interrupt';
$SIG{'ABRT'} = 'interrupt';  $SIG{'STOP'} = 'interrupt';

# Parse command-line options
my $man = 0;
my $help = 0;
my $name = "Unknown";
my $dir = 0;
my $location = "NewMexicoSkies";
my $maestro = 1;
my $verbose = 0;
my $nocoords = 0;
my $port = 3040;

$result = GetOptions(
    "help|?" => \$help, 
    "name=s" => \$name,
    "dir!" => \$dir,
    "maestro!" => \$maestro,
    "verbose" => \$verbose,
    "nocoords!" => \$nocoords,
    "location=s" => \$location,
     man=> \$man) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

# Parse arguments
my $imtype = $ARGV[0];
my $exptime = $ARGV[1];
my $narg = $#ARGV + 1;
pod2usage(2) if $narg != 2;

# Localize
if ($location =~ /NewMexicoSkies/) {
    $theskyx_host = "XXX.XXX.XXX.XXX";
    $theskyx_port = 3040;
}
elsif ($location =~ /Toronto/) {
    $theskyx_host = "localhost";
    $theskyx_port = 3040;
}
else {
    die "Unknown location\n";
}

# Figure out what protocol to use to send commands
if ($maestro) {
    $autocommand = "--maestro";
}
else {
    $autocommand = "--nomaestro";
}

# Determine the IP addresses of the computers hosting cameras
$ip=`camera_info host lens location status | grep $location | grep Nominal | awk '{print \$2}' | sort | uniq | tr '\n' ' '`;
@ip = split('\s+',$ip);
print "Controlling cameras: @ip\n" if $verbose;

# Determine the current working directories for each IP address
$dirinfo = `df_send cameras pwd | awk '{print \$1 ":" \$4}'`;
@dirinfo = split('\s+',$dirinfo);
foreach (@dirinfo) {
    ($inet,$dirname) = split(/:/);
    $udir{$inet} = $dirname;
}

# Get coordinate information from the telescope
print "Getting mount position\n" if $verbose;
my $data = `mount $autocommand --host $theskyx_host position` if !$nocoords;
if (!$data || $data =~ /^Error/) {
    printf(STDERR "Error communicating with the mount or --nocoords flag is set. Position will not be written to header.\n");
    $position_known = 0;
}
else {
    chop($data);
    ($ra,$dec,$alt,$az,$otaside) = split(/\s+/,$data);
    $dec =~ s/\*/d/g;
    $position_known = 1;
    print "Mount position obtained from mount.\n" if $verbose;
}
close(TELESCOPE);

# Last refuge of the damned...
if (!$ra || !$dec || !$alt || !$az) {
    $ra = "00:00:00";
    $dec = "+00d00:00.0";
    $alt = 0.0;
    $az = 0.0;
    $name = "UNKNOWN";
}

# Begin integrations
foreach(@ip) {
    print "Sending expose command to $_\n" if $verbose;
    if ($position_known) {
        `send $_ 7078 "expose -r \"$ra\" -d \"$dec\" -a $alt -z $az -n \"$name\" $imtype $exptime"`;
    }
    else {
        `send $_ 7078 "expose -n \"$name\" $imtype $exptime"`;
    }
}

# Check that integrations have started (DISABLED!)
while(0) {
    foreach(@ip) {
        $result=`send $_ 7078 status`;
        if ($result !~ /progress/i){
            print "ERROR STARTING INTEGRATIONS ON ARRAY $_\n";
            exit(1);
        }
    }
}

# Optionally report progress using a progress bar
if ($exptime > 3 && $verbose) {
    sleep(1);
    my $progress = Term::ProgressBar->new({
            name => 'Progress',
            count => $exptime
        });
    $progress->max_update_rate(1);
    my $next_update = 0;

    for (0..$exptime) {
        $next_update = $progress->update($_) if $_ > $next_update;
        sleep(1);
    }
    $progress->update($exptime) if $exptime >= $next_update;
}
print "  Wall-clock exposure time expired. CCDs should be reading out now.\n" if $verbose;

# Check that integrations have completed
foreach(@ip) {
    print "Checking CCD status to determine whether exposures are completed.\n" if $verbose;
    $result="";
    while($result !~ /idle/i){
        $result=`send $_ 7078 status`;
        sleep(1);
    }
    print "Mac Mini at IP address $_ reports that all integrations are completed.\n" if $verbose;
    $result=`send $_ 7078 list | sed s/^/\[$_\]\\ /`;
    print $result;
}

# Ring the bell
print "\a\a\aIntegrations completed!\n" if ($verbose);
`say "Integrations complete"` if ($verbose);

exit(0);

# Handle interrupts by sending an abort signal to each camera array
sub interrupt {
    my($signal)=@_;
    print "Caught Interrupt\: $signal \n";
    foreach(@ip) {
        `send $_ 7078 abort`;
    }
    print "Integrations aborted.\n";
    exit(1);
} 
__END__


=head1 NAME

all_expose - Obtain CCD data with rich FITS header information for all networked Dragonfly cameras

=head1 SYNOPSIS

all_expose [options] imtype exptime

options:

 -number n
 -name string
 -help
 -man

=head1 ARGUMENTS

=over 8

=item B<imtype>

The type of CCD frame desired. Specify dark, bias, flat or light.

=item B<exptime>

Integration time in seconds.

=back

=head1 OPTIONS

=over 8

=item B<-name object>

Add object name as the value of the OBJNAME FITS header keyword (default = "Unknown")

=item B<-number n>

Number of integrations (default = 1). 

=item B<-help>

Prints a brief help message and exits.

=item B<-man>

Prints the manual page and exits.


=back

=head1 DESCRIPTION

B<all_expose> will integrate CCDs on all networked computers
simultaneously, and will populate each image's FITS header
with information from the telescope (such as coordinates)
Each networked computer must be running a camera_monitor server.

Examples:

  all_expose --name "M101"  
  all_expose --name "M101" --verbose light 1200
  all_expose --name "M101" --nocoords --verbose light 1200

=cut
