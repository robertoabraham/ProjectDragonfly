#!/opt/local/bin/perl

use Getopt::Long;
use Pod::Usage;

# Startup options
$| = 1;

# Parse command-line options
my $verbose = 1;
my $help = 0;
my $man = 0;
my $init = 1;
my $file = "LATEST_FOCUS_POSITIONS.txt";
$result = GetOptions(
    "verbose!" => \$verbose,
    "init!" => \$init,
    "file=s" => \$file,
    "help|?" => \$help,
     man=> \$man) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

# Make sure the information needed actually exists
die "Focus positions file $file not found" if !(-e $file);
$isup=`ps -ae | grep focuser_monitor | grep -v grep`;
chop($isup);
die "Focuser monitor is not running" if (!$isup);

# Reset focus positions
if ($init) {
    print "Initializing focusers\n" if $verbose;
    $result = `all_initfocus`;
    print $result;
}

print "Restoring focus positions\n" if $verbose;
open(FOCUS,"<$file");
while(<FOCUS>){
    ($lens,$pos,$good) = split;
    $lens =~ s/Lens://g;
    $pos =~ s/CurrentPosition://g;
    if ($pos) {
        $result=`df_send focusers "$lens goto $pos"`;
        if ($?) {
            print "Error setting the focus position of camera $lens\n";
        }
        else {
            print "Lens $lens set to $pos\n" if $verbose;
        }
    }
    else {
        print "Error: Focus position of lens $lens is not contained in $file.\n";
    }
}


__END__


=head1 NAME

restore_focus - set focusers to positions given in a text file

=head1 SYNOPSIS

restore_focus [options] 

options:

 --file name
 --[no]verbose
 --[no]init
 --help
 --man

=head1 OPTIONS

=over 8

=item B<--file name>

The name of the text file holding the focus positions. The default is "LATEST_FOCUS_POSITIONS.txt".

=item B<--[no]init>

Initialize focusers prior to trying to restore the focus positions (default is --init).

=item B<--[no]verbose>

Output informational messages (default is --verbose)

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.


=back

=head1 DESCRIPTION

B<restore_focus> sets the focus positions for a set of cameras based on
stored values in a text file. A suitable text file is created at the
end of the all_focus command and it is named LATEST_FOCUS_POSITIONS.txt.
Therefore an easy way to restore the latest focus positions (perhaps after
a power cycle) is:

 restore_focus -f LATEST_FOCUS_POSITIONS.txt

Since the default filename is LATEST_FOCUS_POSITIONS.txt the following
will also work:

 restore_focus

The file format needed in the text file corresponds to what you get by sending
a 'status' command to the focuser monitor and piping this to a text file. The
result is a set of key-value pairs with the keys and values separated by a
colon, and the key-value pairs separated by whitespace. The following keys must
exist: Lens, CurrentPosition, PositionKnown, and these must appear in the file
in the order Lens, CurrentPosition, PositionKnown.

For example, this is a valid file:

 Lens:83F010783  CurrentPosition:21490  PositionKnown:True
 Lens:83F010826  CurrentPosition:21848  PositionKnown:True
 Lens:83F010820  CurrentPosition:21550  PositionKnown:True
 Lens:83F010784  CurrentPosition:21571  PositionKnown:True
 Lens:83F010827  CurrentPosition:21562  PositionKnown:True
 Lens:83F010730  CurrentPosition:21528  PositionKnown:True
 Lens:83F010687  CurrentPosition:21673  PositionKnown:True
 Lens:83F010692  CurrentPosition:21546  PositionKnown:True

=cut
