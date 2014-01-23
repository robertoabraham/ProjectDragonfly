#!/opt/local/bin/perl

use Getopt::Long;
use Pod::Usage;
use File::Basename;
use DateTime;

# Make sure we're not buffering output
$| = 1;

# Parse command-line options
my $verbose = 1;
my $force = 0;
my $dark = 0;
my $mail = 0;
my $minobj = 5;
my $help = 0;
my $man = 0;

$result = GetOptions(
    "verbose!" => \$verbose,
    "force!" => \$force,
    "dark!" => \$dark,
    "mail!" => \$mail,
    "minobj=i" => \$minobj,
    "help|?" => \$help,
     man=> \$man) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

# Parse arguments
@fits_files = @ARGV;
die "File(s) not found" if (@fits_files==0);

# Define the dark frames. These are currently 600s and -5C.
$darkframe{"82F010687"}="/Users/dragonfly/Darks/83F010687_36_dark.fits";
$darkframe{"83F010692"}="/Users/dragonfly/Darks/83F010692_36_dark.fits";
$darkframe{"83F010730"}="/Users/dragonfly/Darks/83F010730_36_dark.fits";
$darkframe{"83F010783"}="/Users/dragonfly/Darks/83F010783_36_dark.fits";
$darkframe{"83F010784"}="/Users/dragonfly/Darks/83F010784_36_dark.fits";
$darkframe{"83F010820"}="/Users/dragonfly/Darks/83F010820_36_dark.fits";
$darkframe{"83F010826"}="/Users/dragonfly/Darks/83F010826_36_dark.fits";
$darkframe{"83F010827"}="/Users/dragonfly/Darks/83F010827_36_dark.fits";

foreach $filename (@fits_files) {

    # Figure out basic information about the file to process
    print "Analyzing $filename\n" if $verbose;
    die "File not found" if !(-e $filename);
    ($file, $directories) = fileparse($filename);
    %mykeys = &getkeys($filename);

    # Check if SExtractor metadata already exists... if so leave it alone
    $already_exists = `modhead $filename ELLIP`;
    chop($already_exists);
    if ($already_exists !~ /does not exist/ && !$force){
        print "Metadata already exists for $filename. Exiting.\n";
        next;
    }

    # Extract serial number which will be used as a key to allow this to work
    # with multiple cameras.
    $file =~ /(^.+)(_.+)(_.+)/;
    $serial_number = $1;
    $serial_number =~ s/^\.\///g; # nuke preceding ./

    # Basic statistical information is stored regardless of file type
    $reg = "[1000:1500,900:1200]";
    %statistics = &getstats($filename . $reg);
    printf("Mean = %8.1f\nMode = %8.1f\n", $statistics{'mean'}, $statistics{'mode'}) if $verbose;
    `modhead $filename MEAN $statistics{'mean'}`;
    `modhead $filename MODE $statistics{'mode'}`;

    # Filter information is stored regardless of file type too
    $filter_name = `camera_info filters location | grep $serial_number | awk '{print \$2}'`;
    chop($filter_name);
    $filter_name =~ s/\(|\)//g;
    `modhead $filename FILTNAM $filter_name`;

    # Seeing is computed if the image is a light frame. This is not allowed to take an
    # arbitrarily long time so we timeout if it isn't finished after a short perior of time.

    `rm -f /var/tmp/store_metadata_file.fits`;
    my $TIMEOUT_IN_SECONDS = 30;   
    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm($TIMEOUT_IN_SECONDS);

        if ($dark && (-e $darkframe{$serial_number})) {
            print "Dark subtracting $darkframe{$serial_number} from $filename\n";
            `imcalc -o /var/tmp/store_metadata_file.fits "%1 %2 -" $filename $darkframe{$serial_number}`; 
        }
        else {
            `cp $filename /var/tmp/store_metadata_file.fits`;
        }

        if ($mykeys{"IMAGETYP"} =~ /light/) {

            # Source extract and filter so we just keep stars
            print "Running SExtractor... " if $verbose;
            `rm -f /var/tmp/store_metadata.txt`;
            $start_time = DateTime->now();
            #`extract /var/tmp/store_metadata_file.fits | tfilter 'CLASS_STAR>0.7 && FLAGS==0' > /var/tmp/store_metadata.txt`;
            # `extract /var/tmp/store_metadata_file.fits > /var/tmp/store_metadata.txt`;
	    `extract /var/tmp/store_metadata_file.fits |  tfilter 'FWHM_IMAGE>0 && FWHM_IMAGE<10 && CLASS_STAR>0.8 && ISOAREA_IMAGE<100 && ISOAREA_IMAGE>20 && FLAGS==0'  > /var/tmp/store_metadata.txt`;

            $end_time = DateTime->now;
            $elapsed_time = $end_time - $start_time;
            $elapsed_time = $elapsed_time->in_units('seconds');
            print "done (took $elapsed_time seconds).\n" if $verbose;

            # FWHM information
            $data = `cat /var/tmp/store_metadata.txt | tfilter 'FLAGS==0 && FWHM_IMAGE>0' | tcolumn FWHM_IMAGE | rstats c e s`;
            $data =~ s/^\s+//g;
            chop($data);
            ($nobj,$seeing,$sigma) = split(/\s+/,$data);
            $seeing = 999. if $seeing =~ /nan/;
            $seeing = 999. if $nobj < $minobj;
            if ($seeing < 999) {
                $sigma = 2.0*$sigma/sqrt($nobj-1);
                printf("Seeing = %5.2f\nSeeingRMS = %5.2f\nNObjects = %d\n", 
                    $seeing,$sigma,$nobj) if $verbose;
            }
            else {
                print(STDERR  "$file: Insufficient number of stars detected.\n");
            }

            # PSF shape information
            $b_over_a = `cat /var/tmp/store_metadata.txt | tfilter 'FLAGS==0 && FWHM_IMAGE>0' | tcolumn ELLIPTICITY | rstats e`;
            chop($b_over_a);
            if (!$b_over_a || $b_over_a =~ /nan/ || $seeing > 900) {
                $b_over_a = 999;
            } 

            # Store the data in the header
            if ($seeing < 999) {
                `modhead $filename SEEING $seeing`;
                $sig = sprintf("%6.4f",$sigma);
                `modhead $filename SSIGMA $sig`;
                `modhead $filename NOBJ $nobj`;
                `modhead $filename ELLIP $b_over_a`;
                `modhead $filename BOVERA $b_over_a`;
            }
            else {
                `modhead $filename SEEING 999`;
                `modhead $filename SSIGMA 999`;
                `modhead $filename NOBJ 0`;
                `modhead $filename ELLIP 999`;
                `modhead $filename BOVERA 999`;
            }
        }

        alarm(0);
    };


    # This only runs if we have had an error
    if ($@) {
        die unless ($@ eq "alarm\n");   # propagate unexpected errors
        print STDERR "Timeout. Could not source extract speedily enough. Inserting dummy values into keywords.\n";
        `modhead $filename SEEING 999`;
        `modhead $filename SSIGMA 999`;
        `modhead $filename NOBJ 0`;
        `modhead $filename ELLIP 999`;
    }

    print "Metadata stored in $filename.\n" if $verbose;

}

# This is a bit gratuitous but useful?
$tmp = "@fits_files";
`imcheck -m $tmp` if $mail;


exit(0);


######### Subroutines ########

sub getkeys {
    my ($file) = @_;
    my $value = '';
    my %key = {};
    my @headerlines = `listhead $file`;
    foreach (@headerlines) {

        ( $kw, $value ) = split( '=', $_);
        $value = &trim($value);         # Nuke whitespace and quote marks
        $value =~ s/(\.*)\/(.*)/$1/;    # Get rid of values with comments
        $value = &trim($value);         # Yes you need to do it again.

        $key{"NAXIS1"} = $value if ($kw =~ /^NAXIS1/);
        $key{"NAXIS2"} = $value if ($kw =~ /^NAXIS2/);
        $key{"DATE"} = $value if ($kw =~ /^DATE/);
        $key{"TEMPERAT"} = $value if ($kw =~ /^TEMPERAT/);
        $key{"RA"} = $value if ($kw =~ /^RA/);
        $key{"DEC"} = $value if ($kw =~ /^DEC/);
        $key{"ALTITUDE"} = $value if ($kw =~ /^ALTITUDE/);
        $key{"EXPTIME"} = $value if ($kw =~ /^EXPTIME/);
        $key{"IMAGETYP"} = $value if ($kw =~ /^IMAGETYP/);
        $key{"FILTNUM"} = $value if ($kw =~ /^FILTNUM/);
        $key{"OBJECT"} = $value if ($kw =~ /^OBJECT/);
        $key{"SERIAL"} = $value if ($kw =~ /^SERIAL/);
        $key{"SOFTWARE"} = $value if ($kw =~ /^SOFTWARE/);

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

sub getstats {
    my ($file) = @_;
    my $value = '';
    my $keyword = 'Mean';
    my %data;
    my $dummy;
    my @lines = `imstats $file`;
    foreach (@lines) {
        chop;
        ( $dummy, $data{"mean"} )  = split( '=', $_) if (/^Mean/);
        ( $dummy, $data{"mode"} )  = split( '=', $_) if (/^Mode/);
        ( $dummy, $data{"sigma"} ) = split( '=', $_) if (/^Sigma/);
        ( $dummy, $data{"min"} )   = split( '=', $_) if (/^Min/);
        ( $dummy, $data{"max"} )   = split( '=', $_) if (/^Max/);
        ( $dummy, $data{"sum"} )   = split( '=', $_) if (/^Sum/);
    }
    return(%data);
}


##########################################################################


__END__

=head1 NAME

store_metadata - compute and store metadata in a FITS image header

=head1 SYNOPSIS

store_metadata [options] filename1 [filename2...]

=head1 ARGUMENTS

=over 8

=item B<filename1 [filename2...]>

FITS files to be analyzed.

=back

=head1 OPTIONS

=over 8

=item B<--minobj>

Minimum number of objects on a frame before the FWHM is computed. If fewer than
minobj objects exist on a frame then the data is dropped from further and a
value of 999 is recorded for the seeing. This is useful because when data is
very far from focus a few insanely bogus detections can occur which result in
crazy FWHM values. The default is 5.

=item B<--[no]verbose>

Print informational messages. Default is --verbose.

=item B<--[no]force>

Recompute metadata if it already exists. Default is --noforce.

=item B<--[no]dark>

Dark subtract the frame. Currently assumes 600s integrations and -5C
integrations, so this is not yet a robust feature. Default is --nodark.

=item B<--help>

Print a brief help message and exit.

=item B<--man>

Print the manual page and exit.

=back

=head1 DESCRIPTION

B<store_metadata> computes the FWHM, mean sky level and other statistical
parameters for an image and stores these in the FITS header.  properties are
stored in the following keywords: SEEING (seeing FWHM in pixels), SSIGMA (RMS
of seeing), NOBJ (number of objects detected), MEAN (mean of central pixels),
MODE (mode of central pixels). The SEEING, SSIGMA and NOBJ values are computed
by running the full frame through SExtractor. 

Only frames with the IMAGETYP keyword having the value "light" are run through
SExtractor. All frames are analyzed for MEAN and MODE though.

In order to keep execution time reasonable a number of corners have been cut.

1. The MEAN and MODE values are computed from the central portion of the
image only.

2. If SExtractor has not completed its analysis of the frame in 30s then 
a value of 999 is recorded for the SEEING and SSIGMA and a value of 0
is recorded for NOBJ.

3. If metadata already exists it is not recomputed unless the --force option
is specified.

EXAMPLES

 Store the metadata in a file, over-writing any existing metadata:

% store_metadata --force 83F010820_46_light.fits 

 Store the metadata in all FITS files in a directory:

% store_metadata *.fits

 Alternatively you can run this on one frame at a time as follows:

% find . -name '*.fits' -exec store_metadata {} \;

=cut
