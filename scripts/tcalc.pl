#!/usr/bin/perl
#
# EXAMPLE
#    tcalc "sqrt((X_IMAGE-1650)**2 + (Y_IMAGE-1250)**2)" < catalog

use Getopt::Long;
use Pod::Usage;

#Parse command-line options
my $colname = "CALC";
my $help = 0;
my $man = 0;
$result = GetOptions(
    "colname=s" => \$colname,
    "help|?" => \$help, 
     man=> \$man) or pod2usage(2);
pod2usage(0) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;
pod2usage(2) if $narg > 1;

$math_string = shift;

$original_math_string = $math_string;
$colnum=0;
$ncol = 0;
$header_printed = 0;
@data_header = ();
@comment_header = ();
while(<STDIN>)
{
    my $line = $_;
    if ($line =~ /^#/) {

        if ($line =~ /^#\!/) {
            push(@comment_header,$line);
            next;
        }

        push(@data_header,$line);
        @fields = split;
        $keyword = $fields[2];

        # Define column numbers to correspond to SExtractor keywords
        # so for example: $col{"FLUX_ISO"}=3 etc.
        $col{$keyword}=$colnum++;

        # Replace each occurrence of the keyword with its corresponding
        # column number. This is actually fairly subtle. Say we have
        # two keywords named NUMBER and FILTER_NUMBER. This can lead
        # to spurious matches unless we are careful to include word
        # markers \b.
        $name = "\$column[$col{$keyword}]";   # A string like "$column[3]"
        $math_string =~ s/\b$keyword\b/$name/g;

        $ncol++;
        
        next;
    }

    if (!$header_printed) {
        for ($i=0;$i<@data_header;$i++) {
            print $data_header[$i];
        }
        print "#  ",@data_header+1," $colname            Result of tcalc      [unspecified]\n";
        for ($i=0;$i<@comment_header;$i++) {
            print $comment_header[$i];
        }
        print "#! tcalc_string = $original_math_string\n";
        print "#! tcalc_string_modified = $math_string\n";
        $header_printed = 1;
    }

    chomp($line);
    @column = split(' ',$line);
    print $line,"  ";
    print eval $math_string;
    print "\n";
}

