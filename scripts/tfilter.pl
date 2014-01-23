#!/usr/bin/perl
#
# EXAMPLE
#
#    tfilter "MAG_AUTO<17 && FLAGS!=0" < foo.txt
#    tfilter "IMAGE_TYPE eq light" < foo.txt
#
use POSIX;

$filter_string = shift;
$original_filter_string = $filter_string;

$colnum=0;
$row=0;

while(<STDIN>)
{
    my $line = $_;
    if ($line =~ /^#/) {

        print $line;

        next if $line =~ /^#\!/;

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
        $filter_string =~ s/\b$keyword\b/$name/g;

        next;

    }

    # Store the filter command as a comment
    print "#! tfilter_string:$original_filter_string\n" if ($row==0);
    print "#! tfilter_string_modified:$filter_string\n" if ($row==0);
    $row++;

    chomp($line);
    @column = split(' ',$line);
    print "$line\n" if eval $filter_string;

}

