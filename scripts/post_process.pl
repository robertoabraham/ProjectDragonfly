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
my $scamp = 0;
my $minobj = 5;
my $help = 0;
my $crop = 1;
my $man = 0;
my $subject = "post process results";

$result = GetOptions(
    "verbose!" => \$verbose,
    "mail!" => \$mail,
    "subject=s" => \$subject,
    "crop!" => \$crop,
    "minobj=i" => \$minobj,
    "help|?" => \$help,
     man=> \$man) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

# Parse arguments
@fits_files = @ARGV;
die "File(s) not found" if (@fits_files==0);

# All operations happen in a temporary directory... this is important
# in practise!
chdir "/var/tmp";
`rm -f *.png *.xml *.SRC *.head *.ldac head.tgz`;

# Add keywords and basic statistical information to all the files
print "Computing mean and mode for every image\n" if $verbose;
foreach $filename (@fits_files) {

    # Figure out basic information about the file to process
    die "File not found" if !(-e $filename);
    ($file, $directories) = fileparse($filename);
    %mykeys = &getkeys($filename);

    $altitude{$filename} = $mykeys{"ALTITUDE"};
    $azimuth{$filename} = $mykeys{"AZIMUTH"};
    $target{$filename} = $mykeys{"TARGET"};
    $target = $target{$filename}; 
    $target =~ s/_/ /; # Nuke the first underscore and make this a global string
    $temperature{$filename} = $mykeys{"TEMPERAT"};

    # Extract serial number which will be used as a key to allow this to work
    # with multiple cameras.
    $file =~ /(^.+)(_.+)(_.+)/;
    $serial_number = $1;
    $serial_number =~ s/^\.\///g; # nuke preceding ./

    # Basic statistical information is stored regardless of file type
    $reg = "[1000:1500,900:1200]";
    %statistics = &getstats($filename . $reg);
    printf("File: $file   Mean: %8.1f    Mode: %8.1f\n", $statistics{'mean'}, $statistics{'mode'}) if $verbose;
    `modhead $filename MEAN $statistics{'mean'}`;
    `modhead $filename MODE $statistics{'mode'}`;
    $mean{$filename} = $statistics{'mean'};

    # Filter information is stored regardless of file type too
    $filter_name = `camera_info filters location | grep $serial_number | awk '{print \$2}'`;
    chop($filter_name);
    $filter_name =~ s/\(|\)//g;
    `modhead $filename FILTNAM $filter_name`;
}

@good_catalogs = ();
@bad_catalogs = ();
foreach $filename (@fits_files) {

    ($basename,$dirname,$suffix) = fileparse($filename);

    # Try to plate solve the image. This needs to be done first because Scamp requires
    # an approximate WCS in the image.
    #
    # Plate solving seems to be more robust if it is done on the central portion of the
    # image so we optionally cut out a bit of the image, plate solve that, then copy
    # the WCS of the solved subset back into the full image. This is a kludge, obviously.
    print "Plate solving $filename\n" if $verbose;
    `rm -f /var/tmp/plate_solve_me.fits`;
    $plate_solve_succeeded{$filename} = "No";
    if ($crop) {
        print "Cropping image to assist in plate solving\n" if $verbose;
        #`fitscopy "$filename\[1176:2175,766:1765\]" /var/tmp/plate_solve_me.fits`;
        `fitscopy "$filename\[1:1500,1:1500\]" /var/tmp/plate_solve_me.fits`;
        print "Calling ImageLink via plate_solve\n" if $verbose;
        `plate_solve --update --nomaestro --time 60 --scale 2.85 /var/tmp/plate_solve_me.fits`;
        $result = `modhead /var/tmp/plate_solve_me.fits CD1_1`;
    }
    else{
        `plate_solve --update --nomaestro --time 60 --scale 2.85 $filename`;
        $result = `modhead $filename CD1_1`;
    }

    if ($?){
        print "ImageLink failed for $filename\n";
    }
    elsif ($result =~ /Keyword does not exist/i) {
        print "Plate solving failed for $filename failed\n";
    }
    else {
        # Successfully plate-solved. 
        $plate_solve_succeeded{$filename} = "Yes";
        push(@good_catalogs,"$basename.ldac");

        # Copy WCS to original image if we were using the cropped image
        `imcopywcs /var/tmp/plate_solve_me.fits $filename` if $crop; 
    }

    # Compute FWHM etc. This happens for all files (even ones that weren't successfully) plate solved.
    print "Running image through source extractor\n" if $verbose;
    `extract -S $filename > "$basename.ldac"`;
    `rm -f foo.ldac`;
    $minobj = 10;
    print "Filtering stellar candidates\n" if $verbose;
    $star_filter = "FWHM_IMAGE>0 \&\& FWHM_IMAGE<10 \&\& CLASS_STAR>0.01 \&\& ISOAREA_IMAGE>40 \&\& ISOAREA_IMAGE<100 \&\& FLAGS==0";
    $cmd = "fitscopy \"$basename.ldac[LDAC_OBJECTS][$star_filter]\" stdout > foo.ldac"; 
    # print "Executing: $cmd\n";
    `$cmd`;
    chomp($data = `tablist 'foo.ldac[LDAC_OBJECTS][col FWHM_IMAGE]' | tail +3 | awk '{print \$2}' | rstats c e s`);
    $data =~ s/^\s+//g;
    ($nobj,$fwhm,$sigma) = split(/\s+/,$data);
    $fwhm = 999 if $fwhm =~ /nan/;
    $fwhm = 999 if $nobj < $minobj;
    if ($fwhm < 999){
        $sigma = 2.0*$sigma/sqrt($nobj-1);
    }
    else {
        $sigma = 999;
    }
    chomp($b_over_a = `tablist 'foo.ldac[LDAC_OBJECTS][col ELLIPTICITY]' | tail +3 | awk '{print \$2}' | rstats e`);
    $b_over_a =~ s/^\s+//g;
    if (!$b_over_a || $b_over_a =~ /nan/ || $seeing > 900) {
        $b_over_a = 999;
    } 
    $fwhm{$filename} = $fwhm;
    $sigma{$filename} = $sigma;
    $nobj{$filename} = $nobj;
    $axrat{$filename} = $b_over_a;

    print "Storing information in headers\n" if $verbose;
    `modhead $filename SEEING $fwhm`;
    `modhead $filename FWHM $fwhm`;
    my $sig = sprintf("%6.4f",$sigma);
    `modhead $filename SSIGMA $sig`;
    `modhead $filename NOBJ $nobj`;
    `modhead $filename ELLIP $b_over_a`;
    `modhead $filename BOVERA $b_over_a`;
}

print "Writing summary to temporary file\n" if $verbose;
open(RESULTS,">/var/tmp/post_process_results.txt");
print RESULTS "#    1  FILENAME\n";
print RESULTS "#    2  FWHM\n";
print RESULTS "#    3  MEAN\n";
print RESULTS "#    4  NOBJ\n";
print RESULTS "#    5  AXIAL_RATIO\n";
print RESULTS "#    6  ALTITUDE\n";
print RESULTS "#    7  AZIMUTH\n";
print RESULTS "#    8  TEMPERATURE\n";
print RESULTS "#    9  PLATE_SOLVED\n";
foreach $camfile (keys %fwhm) {
    printf(RESULTS "%-50s  %5.2f  %5.2f  %8d  %5.2f  %5.1f  %5.1f  %5.1f  %-10s\n",
        $camfile,$fwhm{$camfile},$mean{$camfile},$nobj{$camfile},$axrat{$camfile},
        $altitude{$camfile},$azimuth{$camfile},$temperature{$camfile},
        $plate_solve_succeeded{$camfile});
}
close(RESULTS);

# Create postage stamp montage
print "Generating postage stamps\n" if $verbose;
`rm -f /var/tmp/imcheck.jpg`;
$filenames = "@fits_files\n";
$command = "imcheck $filenames";
print "Executing this command: $command";
$postage_stamp_attachment_command = " -a /var/tmp/imcheck.jpg ";
`$command`;
$postage_stamp_attachment_command = "" if $?;

# Optionally Scamp all files that were successfully plate-solved 
$scamp_attachment_command = "";
if ($scamp) {
    print "Calling Scamp on these files: @good_catalogs\n" if $verbose;
    $nsolved = @good_catalogs;
    if ($nsolved > 0 ) {
        $solved_files = "@good_catalogs";
        print "Scamping @good_catalogs\n" if $verbose;
        `rm -f distort_*.png`;
        `rm -f astr_interror*.png`;
        `rm -f astr_referr*.png`;
        `rm -f psphot_error_*.png`;
        `rm -f scamp.xml`;
        `rm -f *.head`;
        `rm -f *.SRC`;
        `rm -f dall.png`;
        `scamp -c /Users/dragonfly/Dropbox/Astromatic/default.scamp $solved_files`;
        $subject = "[$target] $subject";
        if (!$?) {
            `tar -cvzf headers.tgz *.head post_process_results.txt`;
            `montage -geometry 800x -border 0 -tile 2x4 distort*.png dall.png`;
            $scamp_attachment_command = " -a /var/tmp/imcheck.jpg -a fgroups_1.png -a astr_interror2d_1.png -a dall.png -a headers.tgz ";
        } 
    }
}

# Create all-sky image
print "Creating decorated all-sky image\n" if $verbose;
$first_file = $fits_files[0];
$alt = $altitude{$first_file};
$az = $azimuth{$first_file};
`rm -f /var/tmp/decorated_sky_image.jpg`;
$decorated_sky_attachment_command = " -a /var/tmp/decorated_sky_image.jpg ";
`upload_all_sky_image --altaz $alt $az --noscp decorated_sky_image.jpg`;
$decorated_sky_attachment_command = "" if $?;

# Create image showing the full field.
$full_field_attachment_command =  " -a /var/tmp/nice_image.png ";
$nsolved = @good_catalogs;
if ($nsolved > 0 ) {
	$solved_files = "@fits_files";
    print "Generating a nice image showing the overlapping fields covered by @fits_files\n" if $verbose;
    `rm -f /var/tmp/nice_image.png`;
    `nice_image $solved_files`;
}
$full_field_attachment_command = "" if $?;

# Send the summary email
$subject = "[$target] $subject";
$attachment_commands = " $postage_stamp_attachment_command $full_field_attachment_command $decorated_sky_attachment_command $scamp_attachment_command ";
`mutt -s \"$subject\" $attachment_commands projectdragonfly\@icloud.com < /var/tmp/post_process_results.txt`;

# Clean up temporary files
`rm -f *.png *.xml *.SRC *.head *.ldac head.tgz`;

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
        $key{"AZIMUTH"} = $value if ($kw =~ /^AZIMUTH/);
        $key{"EXPTIME"} = $value if ($kw =~ /^EXPTIME/);
        $key{"IMAGETYP"} = $value if ($kw =~ /^IMAGETYP/);
        $key{"FILTNUM"} = $value if ($kw =~ /^FILTNUM/);
        $key{"OBJECT"} = $value if ($kw =~ /^OBJECT/);
        $key{"SERIAL"} = $value if ($kw =~ /^SERIAL/);
        $key{"SOFTWARE"} = $value if ($kw =~ /^SOFTWARE/);
        $key{"TARGET"} = $value if ($kw =~ /^TARGET/);

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

post_process - basic analysis of raw data images

=head1 SYNOPSIS

post_process [options] filename1 [filename2...]

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

B<post_process> undertakes a number of tasks on images that are useful
for data quality assessment and subsequent pipeline processing. The following
are done:

   1. Basic statistics are computed and stored in the headers. These are: FWHM,
   mean sky level and other statistical parameters for an image and stores
   these in the FITS header.  properties are stored in the following keywords:
   SEEING (seeing FWHM in pixels), SSIGMA (RMS of seeing), NOBJ (number of
   objects detected), MEAN (mean of central pixels), MODE (mode of central
   pixels). The SEEING, SSIGMA and NOBJ values are computed by running the full
   frame through SExtractor. Only frames with the IMAGETYP keyword having the
   value "light" are run through SExtractor. All frames are analyzed for MEAN
   and MODE though.

   2. A World Coordinate System is computed using TheSkyX's ImageLink. This is
   embedded into the header.

   3. A montage of 200x200 postage stamp images in the correct geometric
   positions is created and emailed to the user as an attachment.

   4. A distortion map is created using SCAMP. This is stored in a .head
   auxiliary file (one for each frame) and the set of .head files emailed to
   the user as a tarball.

   5. A map of field positions determined by SCAMP is emailed to the user.

In order to keep execution time reasonable a number of corners have been cut:

1. The MEAN and MODE values are computed from the central portion of the image
only.

2. If SExtractor has not completed its analysis of the frame in 30s then a
value of 999 is recorded for the SEEING and SSIGMA and a value of 0 is recorded
for NOBJ.

3. If metadata already exists it is not recomputed unless the --force option is
specified.

EXAMPLES

 Store the metadata in a file, over-writing any existing metadata:

% post_process --force 83F010820_46_light.fits 

 Store the metadata in all FITS files in a directory:

% post_process *.fits

 Alternatively you can run this on one frame at a time as follows:

% find . -name '*.fits' -exec post_process {} \;

=cut
