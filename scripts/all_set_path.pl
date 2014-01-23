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
    "location=s" => \$location,
    "help|?" => \$help, 
     man=> \$man) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

# Determine the IP addresses of the computers hosting cameras
$ip=`camera_info host lens location status | grep $location | grep Nominal | awk '{print \$2}' | sort | uniq | tr '\n' ' '`;
@ip = split('\s+',$ip);

# setup the directories
$today = `date \"+%Y-%m-%d\"`;
chop($today);
$today_dir = "/Users/dragonfly/Data/$today";

foreach(@ip) {
    print "Creating directory $today_dir on $_\n" if $verbose;
    `send $_ 7078 "mkdir $today_dir"`;
    `send $_ 7078 "cd $today_dir"`;
    $result=`send $_ 7078 pwd`;
    print $result;
    die "Error accessing directory" if ($result !~ $today_dir); 
}

exit(0);

__END__


=head1 NAME

all_set_path - Create directories on remote machines and use them for data storage.

=head1 SYNOPSIS

all_set_path [options] 

options:

 -location name
 -help
 -man

=head1 OPTIONS

=over 8

=item B<-location name>

Location of the observatory. Currently NewMexicoSkies and Toronto are supported.

=item B<-help>

Prints a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<all_set_path> sends a message to the camera monitor servers
on all machines hosting cameras and instructs them to create
a directory (named YY-MM-DD under the Data directory) and to
write the night's data there.

=cut
