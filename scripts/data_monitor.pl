#!/usr/bin/perl

use Getopt::Long qw(:config require_order);  
use Pod::Usage;
use IO::Socket;

$exe_bin = "/usr/local/bin";

#Avoid zombie children when forking
$SIG{CHLD} = 'IGNORE';

#Parse command-line options
my $port = 7076;
my $echo = 0;
my $help = 0;
my $man = 0;
$result = GetOptions(
    "echo!" => \$echo,
    "port=i" => \$port,
    "help|?" => \$help, 
man=> \$man) or pod2usage(2);
pod2usage(0) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

#Open socket
my $sock = new IO::Socket::INET (
    LocalPort => $port,
    Proto => 'tcp',
    Listen => 1,
    Reuse => 1,
);
die "Could not create socket: $!\n" unless $sock;

#Wait for commands
print "Data monitor listening on port $port...\n";
$exe_bin = "/usr/local/bin";
while (my $connection = $sock->accept) {
    print "Client connected at ",scalar(localtime),"\n";
    while(<$connection>){
        chop;
        @fields = split;
        $command = $fields[0];
        $command =~ s/\s+$//;
        shift(@fields);
        $argument = "@fields";

        print "Client issues command $command with argument $argument\n";

        if ($command =~ /store_metadata/c) {
            if ($pid = fork) {
                print $connection "Metadata will be calculated and embedded in $argument\n";
            } else {
                my $thiscommand = "$exe_bin/store_metadata --force --mail --dark $argument; exit\n";
                system("$thiscommand"); 
                exit(0);
            }
            print $connection "Done.\n"; 
        }

        if ($command =~ /post_process/c) {
            if ($pid = fork) {
                print $connection "Post-processing of $argument begun\n";
            } else {
                my $thiscommand = "$exe_bin/post_process $argument; exit\n";
                system("$thiscommand"); 
                exit(0);
            }
            print $connection "Done.\n"; 
        }

        elsif ($command =~ /listhead|header/i) {
            if (-e $argument) {
                my $info = `listhead $argument`;
                chop($info);
                print $connection $info;
            }
            else {
                print $connection "[$my_ip] Error: file not found\n";
            }
            print $connection "Done.\n"; 
        }

        elsif ($command =~ /report/i) {
            my $command = "email_report $argument";
            `$command`;
            print $connection "Done.\n"; 
        }

        else {
            print $connection "Unknown command\n";
            print $connection "Done.\n"; 
        }

    }
    close $connection;
    print "Client disconnected\n";
}


__END__

=head1 NAME

data_monitor - monitor incoming data from Project Dragonfly

=head1 SYNOPSIS

focuser_monitor [OPTIONS] 

=head1 OPTIONS

=over 8

=item B<--port number>

Port to listen for commands on. The default is 7070.

=item B<--echo --noecho>

Display output from commands sent to the server. The default is --noecho.

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<data_monitor> executes commands on incoming data from Project Dragonfly.

Commands can be sent to the B<data_monitor> in a myriad number of ways (e.g. using
telnet) though a particularly convenient way is to use the dragonfly command
B<df_send> which should already know the default TCP address and port number of
the data monitor.
 
=head1 EXAMPLES

%df_send dataserver "store_metadata /var/tmp/foo.fits"

=cut

