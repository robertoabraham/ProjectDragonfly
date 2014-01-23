#!/opt/local/bin/perl

use Getopt::Long;
use Pod::Usage;

# Parse command-line options
my $help = 0;
my $man = 0;
my $min_exposure = 30;
my $arcmin = 5;

$result = GetOptions(
    "help|?" => \$help, 
     man=> \$man) or pod2usage(2);
pod2usage(0) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

# Organize darks

print " ----------------- DARK FRAMES ------------------\n";
`summarize *_dark.fits > /var/tmp/darks.txt`;
if ($?) {
    print "No files found.\n";
}
else
{
     chomp(@cameras = `tcolumn SERIAL_NUMBER < /var/tmp/darks.txt | sort | uniq`);
    foreach $camera (@cameras) {

        print "Camera: $camera\n";

        my $cmd = "tfilter \"SERIAL_NUMBER eq \'$camera\'\" < /var/tmp/darks.txt | tcolumn TEMPERATURE | sort | uniq";
        chomp(my $temperatures = `$cmd`);
        $temperatures =~ s/\n/ /;
        print "Temperatures: $temperatures\n";

        my $cmd = "tfilter \"SERIAL_NUMBER eq \'$camera\'\" < /var/tmp/darks.txt | tcolumn EXPOSURE | sort -n | uniq | tr '\\n' ' '";
        chomp(my $exptime = `$cmd`);

        print "Files:\n";
        @exptime = split(' ',$exptime);
        foreach $time (@exptime) {
            my $cmd = "tfilter \"SERIAL_NUMBER eq \'$camera\' && EXPOSURE == $time\" < /var/tmp/darks.txt | tcolumn FILENAME | tr '\\n' ' '";
            chomp(my $files = `$cmd`);
            printf("%10.1f sec: %s\n",$time,$files);
        }
        print "\n";
    }
}

# Organize flats
print " ----------------- FLAT FRAMES ------------------\n";
`summarize *_flat.fits > /var/tmp/flats.txt`;
if ($?) {
    print "No files found.\n";
}
else
{
    chomp(@cameras = `tcolumn SERIAL_NUMBER < /var/tmp/flats.txt | sort | uniq`);
    foreach $camera (@cameras) {

        print "Camera: $camera\n";

        my $cmd = "tfilter \"SERIAL_NUMBER eq \'$camera\'\" < /var/tmp/flats.txt | tcolumn TEMPERATURE | sort | uniq";
        chomp(my $temperatures = `$cmd`);
        $temperatures =~ s/\n/ /;
        print "Temperatures: $temperatures\n";

        my $cmd = "tfilter \"SERIAL_NUMBER eq \'$camera\'\" < /var/tmp/flats.txt | tcolumn EXPOSURE | sort -n | uniq | tr '\\n' ' '";
        chomp(my $exptime = `$cmd`);

        print "Files:\n";
        @exptime = split(' ',$exptime);
        foreach $time (@exptime) {
            my $cmd = "tfilter \"SERIAL_NUMBER eq \'$camera\' && EXPOSURE == $time\" < /var/tmp/flats.txt | tcolumn FILENAME | tr '\\n' ' '";
            chomp(my $files = `$cmd`);
            printf("%10.1f sec: %s\n",$time,$files);
        }
        print "\n";
    }
}


__END__

=head1 NAME

jorganize - organize files in a directory for pipelining and output results in JSON format

=head1 SYNOPSIS

jorganize

=head1 OPTIONS

=over 8

=item B<-help>

Prints a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<jorganize> is a high-level routine that attempts to group files together so
they can be stacked to improve signal-to-noise.  The results are output in
JSON format.

=cut

