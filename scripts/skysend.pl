#!/usr/bin/perl

use Getopt::Long qw(:config require_order);  
use Pod::Usage;
use IO::Socket;

# Do not buffer I/O
$| = 1;  

#Parse command-line options
my $help = 0;
my $man = 0;
$result = GetOptions(
    "help|?" => \$help, 
     man=> \$man) or pod2usage(2);
pod2usage(0) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

my $address = shift;
my $filename = shift;

$data = `cat $filename`;
chop($data);

$sock = new IO::Socket::INET->new(
    PeerAddr => $address,
    PeerPort => 3040,
    Proto => "tcp",
    Blocking => 1,
    Type => SOCK_STREAM
);
die "Could not initiate communication with TheSkyX using socket: $!\n" unless $sock;
$sock->autoflush(1);  # Send immediately

print $sock "$data\n";

$sock->recv($msg,1000);
print $msg;

close($sock);
sleep(1); # Extra time to ensure socket closes properly

__END__

=head1 NAME

skysend - send contents of a JavaScript file to TheSkyX on a remote machine

=head1 SYNOPSIS

skysend address file 


=head1 ARGUMENTS

=over 8

=item B<address>

IP address of host.

=item B<file>

JavaScript file containing TheSkyX commands.

=back

=head1 OPTIONS

=over 8

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<send> skysend sends the contents of a file to TheSkyX's TCP server and displays the output
from the command.

=head1 EXAMPLE

skysend localhost myfile.js

=cut

