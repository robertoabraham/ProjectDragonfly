#!/opt/local/bin/perl

use Getopt::Long;
use Pod::Usage;

# Parse command-line options
my $man = 0;
my $help = 0;
my $location = "NewMexicoSkies";
my $verbose = 0;
my $port = 3040;

$result = GetOptions(
    "help|?" => \$help, 
    "verbose" => \$verbose,
    "file=s" => \$focus_file,
     man=> \$man) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

$server = shift;
$message = shift;

if ($server =~ /camera/) {
    # Determine the IP addresses of the computers hosting cameras
	$ip=`camera_info host lens location status | grep $location | grep Nominal | awk '{print \$2}' | sort | uniq | tr '\n' ' '`;
	@ip = split('\s+',$ip);
    # Send the message to each server
	foreach(@ip) {
		$result = `send $_ 7078 "$message"`;
		print $result;
	}
}
elsif ($server =~ /focuser/) {
	$result = `send XXX.XXX.XXX.XXX XXXX "$message"`;
	print $result;
}
elsif ($server =~ /dataserver/) {
	$result = `send XXX.XXX.XXX.XXX XXXX "$message"`;
	print $result;
}
else {
	print "Error: Unknown server.\n";
}


exit(0);

__END__


=head1 NAME

df_send - Send a TCP/IP message to a dragonfly server

=head1 SYNOPSIS

df_send [options] server message 

options:

 -help
 -man

=head1 ARGUMENTS 

=over 8

=item B<server>

One of "focusers", "cameras", "dataserver".

=item B<message>

A message known to a server. The message must be enclosed in quotes.

=back


=head1 OPTIONS

=over 8

=item B<-help>

Prints a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<df_send> sends a message to dragonfly servers. Known servers include:
"focusers", "cameras", "dataserver".

=cut
