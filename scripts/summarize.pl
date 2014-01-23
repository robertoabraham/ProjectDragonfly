#!/usr/bin/perl

# SUMMARIZE - Summarize properties of a set of FITS files
#
# EXAMPLE
#    summarize *.fits
#
#
# To populate with metadata that this displays:
#
# $ find . -name '*_light.fits' -exec store_metadata \{\} \;
# $ find . -name '*_flat.fits' -exec store_metadata \{\} \;
# $ find . -name '*_light.fits' -exec plate_solve \{\} \;

use File::Basename;
use File::Spec;
use Cwd;
use Time::Local;
use Data::Dumper;
use Getopt::Long qw(:config require_order);  # The require_order flag stops negative arguments from being treated as flags
use Pod::Usage;

# Parse command-line options
my $positions = 0;
my $directory = 1;
my $bias_subtract = 0;
my $comment = "";
my $help = 0;
my $man = 0;

$help = 1 if $#ARGV == -1;

$result = GetOptions(
    "positions" => \$positions,
    "bias_subtract!" => \$bias_subtract,
    "directory!" => \$directory,
    "comment=s" => \$comment,
    "help|?" => \$help, 
     man=> \$man) or pod2usage(2);
pod2usage(0) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;


@fits_files = @ARGV;
die "File(s) not found" if (@fits_files==0);

foreach $fits_file (@fits_files) {

    die "File(s) not found" if !(-e $fits_file);

    ($basename,$dirname) = fileparse($fits_file);
    #$basename =~ s/\.fits$//g;
    #$basename =~ s/\.FIT$//g;

    next if ($fits_file !~ /\.fits$|\.FIT$|\.fit$|\.FITS$/); 

    $file = "$dirname$basename";
    $filename{$basename} = "$file";

    %mykeys = &getkeys($file);
    $naxis1{$basename}   = $mykeys{"NAXIS1"};
    $naxis2{$basename}   = $mykeys{"NAXIS2"};
    $date{$basename}     = $mykeys{"DATE"}; 
    $ccdtemp{$basename}  = $mykeys{"TEMPERAT"};
    $ra{$basename}       = $mykeys{"OBJCTRA"};
    $dec{$basename}      = $mykeys{"OBJCTDEC"};
    $altitude{$basename} = $mykeys{"ALTITUDE"};
    $exptime{$basename}  = $mykeys{"EXPTIME"};
    $imagetype{$basename}= $mykeys{"IMAGETYP"};
    $filter{$basename}   = $mykeys{"FILTNUM"};
    $filtname{$basename} = $mykeys{"FILTNAM"};
    $target{$basename}   = $mykeys{"TARGET"};
    $serial{$basename}   = $mykeys{"SERIAL"};
    $seeing{$basename}   = $mykeys{"SEEING"};
    $nobj{$basename}     = $mykeys{"NOBJ"};
    $ellip{$basename}    = $mykeys{"ELLIP"};
    $mean{$basename}     = $mykeys{"MEAN"};

    if ($mean{$basename} && $bias_subtract) {
        $bias = `camera_info bias | grep $serial{$basename} | awk '{print \$2}'`;
        $mean{$basename} -= $bias;
    }

    if ($exptime{$basename} > 0.0) {
        $rate{$basename} = $mean{$basename}/$exptime{$basename};
    }
    else {
        $rate{$basename} = "---";
    }

    $haswcs{$basename} = "Y";
    $check_wcs = `modhead $fits_file CRPIX1`;
    $haswcs{$basename} = "N" if ($check_wcs =~ /does not exist/);

}


$count = 1;

foreach $key (sort { datecompare($a,$b) } keys %exptime) {

    # Deal with missing information
    unless ($filtname{$key}){
        $filtname{$key} = "?";
    }
    $filtname{$key} =~ s/Sloan//g;
    $filtname{$key} =~ s/WhiteLight/W/g;

    unless ($serial{$key}){
        $serial{$key} = "UNKNOWN";
    }

    unless ($ra{$key}){
        $ra{$key}  = "---";
        $dec{$key} = "---";
    }

    unless ($target{$key}){
         $target{$key}  = "---";
    }

    unless ($seeing{$key}){
         $seeing{$key}  = "---";
         $ellipticity{$key}  = "---";
    }

    if($altitude{$key}){
        $altitude{$key} = sprintf("%5.2f",$altitude{$key});
    }
    else {
        $altitude{$key}  = "---";
    }

    unless ($mean{$key}){
        $mean{$key}  = "---";
    }

    unless ($rate{$key}){
        $rate{$key}  = "---";
    }

    # Deal with overly-long target names (special cases only)
    $target{$key} = "Mouse_click" if $target{$key} =~ /Mouse_click_position/;


    # OUTPUT RESULTS

    if ($count == 1) {
        $row = 1;
        printf("# %d NUMBER\n",$row++);
        printf("# %d NX\n",$row++);
        printf("# %d NY\n",$row++);
        printf("# %d EXPOSURE\n",$row++);

        printf("# %d SEEING\n",$row++);
        printf("# %d ELLIPTICITY\n",$row++);
        printf("# %d NOBJ\n",$row++);

        printf("# %d MEAN\n",$row++);
        printf("# %d RATE\n",$row++);

        printf("# %d IMAGE_TYPE\n",$row++);
        printf("# %d SERIAL_NUMBER\n",$row++);
        printf("# %d WCS_IN_HEADER\n",$row++);
        
        #printf("# %d FILTER_NUMBER (0=UNKNOWN, 1=G, 2=R, 3=IRBLOCK, 4=CLEAR)\n",$row++);
        printf("# %d FILTER_NAME\n",$row++);
        printf("# %d TEMPERATURE\n",$row++);
        printf("# %d DATE\n",$row++);

        printf("# %d RA\n",$row++) if $positions;
        printf("# %d DEC\n",$row++) if $positions;

        printf("# %d TARGET\n",$row++); 
        printf("# %d ALTITUDE\n",$row++);

        printf("# %d FILENAME\n",$row++);

        printf("#! summarize_last_directory:%s\n",Cwd::realpath($dirname));
        printf("#! summarize_is_bias_subtracted:%d\n",$bias_subtract) if $bias_subtract;
        printf("#! summarize_comment:%s\n",$comment) if $comment;
    }

    printf("%5d",$count++);
    printf("%6s",$naxis1{$key});
    printf("%6s",$naxis2{$key});
    printf("%7.2f",$exptime{$key});
    if ($seeing{$key} > 0.001 && $seeing{$key} < 998) {
        printf("%7.2f",$seeing{$key});
        printf("%7.3f",$ellip{$key});
        printf("%8d",$nobj{$key});
    }
    elsif ($seeing{$key} > 998 && $seeing{$key} < 1000) {
        printf("%7d",$seeing{$key});
        printf("%7d",$ellip{$key});
        printf("%8d",$nobj{$key});
    }
    else {
        printf("%7s","---");
        printf("%7s","---");
        printf("%8s","---");
    }

    if ($mean{$key} =~ /\-\-\-/) {
        printf("%10s",$mean{$key});
    } else {
        printf("%10.2f",$mean{$key});
    }

    if ($rate{$key} =~ /\-\-\-/) {
        printf("%10s",$rate{$key});
    } else {
        printf("%10.2f",$rate{$key});
    }

    printf("%10s",$imagetype{$key});
    printf("%10s",$serial{$key});

    printf("%3s",$haswcs{$key});
    printf("%7s",$filtname{$key});
    printf("%6.1f",$ccdtemp{$key});
    printf("%22s",$date{$key});

    printf("%13s",$ra{$key}) if $positions;
    printf("%13s",$dec{$key}) if $positions;

    printf("  %-14s",$target{$key});
    printf("%6s",$altitude{$key});

    if ($directory) {
        printf("  %-40s",$filename{$key});
    }
    else{
        printf("  %-40s",$key);
    }


    print("\n");


}


sub getkey {
    my ($keyword,$file) = @_;
    my $value = '';
    @headerlines = `listhead $file`;
    foreach (@headerlines) {
        if ( /^$keyword/ ) {
            ( $kw, $value ) = split( '=', $_);
            $value = &trim($value);         # Nuke whitespace and quote marks
            $value =~ s/(\.*)\/(.*)/$1/;    # Get rid of values with comments
            $value = &trim($value);         # Yes you need to do it again.
            break;
        }
    }
    return($value);
}


sub getkeys {
    my ($file) = @_;
    my $value = '';
    my %key = {};
    @headerlines = `listhead $file`;
    foreach (@headerlines) {

        ( $kw, $value ) = split( '=', $_);
        $value = &trim($value);         # Nuke whitespace and quote marks
        $value =~ s/(\.*)\/(.*)/$1/;    # Get rid of values with comments
        $value = &trim($value);         # Yes you need to do it again.

        $key{"NAXIS1"} = $value if ($kw =~ /^NAXIS1/);
        $key{"NAXIS2"} = $value if ($kw =~ /^NAXIS2/);
        $key{"DATE"} = $value if ($kw =~ /^DATE/);
        $key{"TEMPERAT"} = $value if ($kw =~ /^TEMPERAT/);
        $key{"OBJCTRA"} = $value if ($kw =~ /^OBJCTRA/);
        $key{"OBJCTDEC"} = $value if ($kw =~ /^OBJCTDEC/);
        $key{"ALTITUDE"} = $value if ($kw =~ /^ALTITUDE/);
        $key{"EXPTIME"} = $value if ($kw =~ /^EXPTIME/);
        $key{"IMAGETYP"} = $value if ($kw =~ /^IMAGETYP/);
        $key{"FILTNUM"} = $value if ($kw =~ /^FILTNUM/);
        $key{"FILTNAM"} = $value if ($kw =~ /^FILTNAM/);
        $key{"TARGET"} = $value if ($kw =~ /^TARGET/);
        $key{"SERIAL"} = $value if ($kw =~ /^SERIAL/);
        $key{"SEEING"} = $value if ($kw =~ /^SEEING/);
        $key{"ELLIP"} = $value if ($kw =~ /^ELLIP/);
        $key{"NOBJ"} = $value if ($kw =~ /^NOBJ/);
        $key{"MEAN"} = $value if ($kw =~ /^MEAN/);
        $key{"MODE"} = $value if ($kw =~ /^MODE/);

    }
    return %key;
}


sub trim($)
{
        my $string = shift;
        $string =~ s/^\s+//;
        $string =~ s/^\'//;
        $string =~ s/\s+$//;
        $string =~ s/\'$//;
        $string =~ s/\s//;
        return $string;
}


# Sort by date
sub datecompare {

    $aa = $date{$a};
    $aa =~ /(\d{4})\-(\d{2})\-(\d{2})T(\d{2}):(\d{2}):(\d{2})/;
    $aayear = $1;
    $aamonth = $2;
    $aaday = $3;
    $aahour = $4;
    $aamin = $5;
    $aasec = $6;

    $bb = $date{$b};
    $bb =~ /(\d{4})\-(\d{2})\-(\d{2})T(\d{2}):(\d{2}):(\d{2})/;
    $bbyear = $1;
    $bbmonth = $2;
    $bbday = $3;
    $bbhour = $4;
    $bbmin = $5;
    $bbsec = $6;
    
    $c = timelocal($aasec,$aamin,$aahour,$aaday,$aamonth-1,$aayear-1900);
    $d = timelocal($bbsec,$bbmin,$bbhour,$bbday,$bbmonth-1,$bbyear-1900);

    $c <=> $d;
}



__END__

=head1 NAME

summarize - summarize information for a collection of FITS frames

=head1 SYNOPSIS

summarize [options] file1.fits ... filenN.fits

summarize [options] *.fits

=head1 OPTIONS

=over 8

=item B<--[no]directory>

Include directory in filenames.

=item B<--bias_subtract>

Bias subtract data for cameras with known bias levels.
Unown biases will be assumed to be 0.

=item B<--positions>

Output target RA and Dec stored in the FITS header. This is only a crude estimate based
on the reported mount position.

=item B<--comment string>

Include string as a comment in the output.

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.


=back

=head1 DESCRIPTION

B<summarize> prints a tabular summary of information for a 
collection of FITS images. The table is in SExctractor ASCII
catalog format. In addition to quanties stored in the FITS
header, image statistics are also reported, computed within 
a sub-frame. 

=cut

