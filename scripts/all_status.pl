#!/opt/local/bin/perl

use Getopt::Long qw(:config require_order);   # The require_order flag stops negative arguments from being treated as flags
use Pod::Usage;

# Parse command-line options
my $location = "NewMexicoSkies";
my $man = 0;
my $help = 0;
my $port = 3040;

$result = GetOptions(
    "location=s" => \$location,
    "help|?" => \$help, 
     man=> \$man) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

# Determine the IP addresses of the computers hosting cameras
$ip=`camera_info host lens location status | grep $location | grep Nominal | awk '{print \$2}' | sort | uniq | tr '\n' ' '`;
@ip = split('\s+',$ip);

foreach(@ip) {
    $result=`send $_ 7078 "status"`;
    $result =~ s/Temperature: //g;
    $result =~ s/\]/\]\n/g;
    $result =~ s/\n\s+/\n/g;
    $result =~ s/\[$_\]\n//g;
    print "[$_]\n$result";
}

exit(0);

__END__


=head1 NAME

all_status - Determine status of all cameras in a Dragonfly array.

=head1 SYNOPSIS

all_regulate [options] setpoint

options:

 -location name
 -help
 -man

=head1 OPTIONS

=over 8

=item B<-location> name

location of the observatory. Currently NewMexicoSkies and Toronto are supported.

=item B<-help>

Prints a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<all_status> prints the status of all cameras in a Dragonfly array.

=cut
