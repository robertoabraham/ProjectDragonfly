#!/opt/local/bin/perl

use Getopt::Long;
use Pod::Usage;
use Switch;

# Parse command-line options
my $man = 0;
my $help = 0;
my $verbose = 0;

$result = GetOptions(
    "temperature=f" => \$temperature,
    "verbose" => \$verbose,
    "help|?" => \$help, 
     man=> \$man) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

# Parse arguments
my $narg = $#ARGV + 1;
pod2usage(2) if $narg > 1;

$serialno = $ARGV[0];

# Define the temperature function
$info = `camera_info focusfunc location | grep $serialno`;
die "Unknown serial number, stopped" if !$info;
chop($info);
$info =~ /(.+)\"(.+)\"/;
$func = eval($2);

# Get current temperature at New Mexico Skies if it isn't already defined
if (!$temperature) {
    $temperature = `nms_temperature`;
    chop($temperature);
}

# Return estimated focus position
if ($temperature) {
    $val = (&{$func}($temperature));
    print int($val),"\n";
    exit(0);
}
else {
    print STDERR "Unable to determine temperature. Returning default setpoint.\n";
    $info = `camera_info focus_start | grep $serialno | awk '{print \$2}'`;
    chop($info);
    print $info,"\n";
    exit(1);
}

##########################################################################


__END__

=head1 NAME

predict_focus - Predict the best focus position for a camera lens at New Mexico Skies.

=head1 SYNOPSIS

predict_focus serial

options:
 
 -temperature
 -help
 -man

=head1 ARGUMENTS

=over 8

=item B<serial>

Serial number of the CCD camera.

=back

=head1 OPTIONS

=over 8

=item B<-temperature float>

Temperature in degrees Fahrenheit. 

=item B<-verbose>

Print informational messages.

=item B<-help>

Print a brief help message and exit.

=item B<-man>

Print the manual page and exit.

=back

=head1 DESCRIPTION

B<predict_focus> predicts the best focus position for a specified focuser. If
a temperature is not specified using the -t option then the current temperature at
New Mexico Skies (determined over the internet) is used to predict the best focus
position. If this temperature cannot be obtained for some reason an error message
is sent to stderr and the default position is returned.

=cut
