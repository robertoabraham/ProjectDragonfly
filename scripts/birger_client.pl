#!/usr/bin/perl

use Getopt::Long qw(:config require_order);  
use Pod::Usage;
use IO::Socket;

#Parse command-line options
my $help = 0;
my $man = 0;
my $port = 7070;
my $echo = 0;
$result = GetOptions(
    "port=i" => \$port,
    "help|?" => \$help, 
     man=> \$man) or pod2usage(2);
pod2usage(0) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

use IO::Socket;
my $sock = new IO::Socket::INET (
    PeerAddr => 'XXX.XXX.XXX.XXX',
    PeerPort => '7070',
    Proto => 'tcp'
);
die "Could not create socket: $!\n" unless $sock;
$sock->autoflush(1);  # Send immediately

print $sock "@ARGV\n";
while(<$sock>) {
    last if /^Done\./; 
    print 
};
close($sock);

__END__

=head1 NAME

birger_client - send commands to a networked focus controller 

=head1 SYNOPSIS

birger_client [OPTIONS] lens_number [command [argument]]

=head1 ARGUMENTS

=over 8

=item B<lens_number>

The number of the lens being sent the command.

=item B<command [argument]>

A command (plus argument, if needed) known to the 'birger' program. If no command
is given then the current lens position is reported (which is the default behavior
of the 'birger' program).

=back

=head1 OPTIONS

=over 8

=item B<--port number>

Port to listen for commands on. The default is 7070.

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<birger_client> sends a command over the network to a server which is managing
an array of Birger focus controllers. In order for this to work the machine
with with the focus controllers physically connected to it must be running the
B<birger_server> daemon. 

=head1 EXAMPLES

=over 4

% birger_client 83F010612 init         (initializes controller attached to camera with serial number 83F010612)

% birger_client 83F010612 goto 500     (sends lens attached to camera 83F010612 to focus step 500)

% birger_client 83F010612              (returns current position of lens attached to camera 83F010612)

% birger_client 83F010612 status       (returns information for lens attached to camera 83F010612)

=back

=cut

