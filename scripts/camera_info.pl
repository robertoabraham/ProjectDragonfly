#!/opt/local/bin/perl

use Getopt::Long;
use Pod::Usage;
use Switch;

# Parse command-line options
my $man = 0;
my $help = 0;
my $location = "NewMexicoSkies";
$result = GetOptions(
    "camera=s" => \$camera, 
    "location=s" => \$location, 
    "help|?" => \$help, 
     man=> \$man) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

$arg1 = $ARGV[0];

################## Active NMS cameras below here ####################

# ARRAY A CAMERAS
 
$model{"83F010783"}         = "STF-8300M";
$location{"83F010783"}      = "NewMexicoSkies";
$nickname{"83F010783"}      = "A1";                         
$detector{"83F010783"}      = "KAF-8300ME";
$wheel{"83F010783"}         = "none";
$format{"83F010783"}        = "3326x2504";
$pixel_size{"83F010783"}    = "5.4,5.4";
$filters{"83F010783"}       =  "(SloanG)";   
$interface{"83F010783"}     = "USB";
$focuser_model{"83F010783"} = "birger";
$focuser_port{"83F010783"}  = "/dev/cu.USA49Wfd12P2.2";    # USB - Serial adapter A
$focus_start{"83F010783"}   = 21750;
$host{"83F010783"}          = "XXX.XXX.XXX";
$lens{"83F010783"}          = "CanonEF400f2.8";
$status{"83F010783"}        = "Nominal";
$bias{"83F010783"}          = 815;
$flat{"83F010783"}          = "";
$array{"83F010783"}         = "A";
$arraydir{"83F010783"}      = "/Volumes/ArrayA";

$model{"83F010687"}         = "STF-8300M";
$location{"83F010687"}      = "NewMexicoSkies";
$nickname{"83F010687"}      = "A2";
$detector{"83F010687"}      = "KAF-8300ME";
$wheel{"83F010687"}         = "none";
$format{"83F010687"}        = "3326x2504";
$pixel_size{"83F010687"}    = "5.4,5.4";
$filters{"83F010687"}       =  "(SloanG)";   
$interface{"83F010687"}     = "USB";
$focuser_model{"83F010687"} = "birger";
$focuser_port{"83F010687"}  = "/dev/cu.USA49Wfd12P3.3";    # USB - Serial adapter A
$focus_start{"83F010687"}   = 21720;   # T=27F
$host{"83F010687"}          = "XXX.XXX.XXX";
$lens{"83F010687"}          = "CanonEF400f2.8";
$status{"83F010687"}        = "Nominal";
$bias{"83F010687"}          = 738;
$flat{"83F010687"}          = "";
$array{"83F010687"}         = "A";
$arraydir{"83F010687"}      = "/Volumes/ArrayA";

$model{"83F010820"}         = "STF-8300M";
$location{"83F010820"}      = "NewMexicoSkies";
$nickname{"83F010820"}      = "A3";
$detector{"83F010820"}      = "KAF-8300ME";
$wheel{"83F010820"}         = "none";
$format{"83F010820"}        = "3326x2504";
$pixel_size{"83F010820"}    = "5.4,5.4";
$filters{"83F010820"}       = "(SloanG)";   
$interface{"83F010820"}     = "USB";
$focuser_model{"83F010820"} = "birger";
$focuser_port{"83F010820"}  = "/dev/cu.USA49Wfd12P4.4";    # USB - Serial adapter A
$focus_start{"83F010820"}   = 21680;     # T=27F
$host{"83F010820"}          = "XXX.XXX.XXX";    # temporarily on mount control computer
$lens{"83F010820"}          = "CanonEF400f2.8";
$status{"83F010820"}        = "Nominal";
$bias{"83F010820"}          = 688;
$flat{"83F010820"}          = "";
$array{"83F010820"}         = "A";
$arraydir{"83F010820"}      = "/Volumes/ArrayA";

$model{"83F010827"}         = "STF-8300M";                
$location{"83F010827"}      = "NewMexicoSkies";
$nickname{"83F010827"}      = "B1";
$detector{"83F010827"}      = "KAF-8300ME";
$wheel{"83F010827"}         = "none";
$format{"83F010827"}        = "3326x2504";
$pixel_size{"83F010827"}    = "5.4,5.4";
$filters{"83F010827"}       =  "(SloanG)";   
$interface{"83F010827"}     = "USB";
$focuser_model{"83F010827"} = "birger";
$focuser_port{"83F010827"}  = "/dev/cu.USA49Wfd12P1.1";   # USB - Serial adapter B 
$focus_start{"83F010827"}   = 21730;
$host{"83F010827"}          = "XXX.XXX.XXX"; 
$lens{"83F010827"}          = "CanonEF400f2.8";
$status{"83F010827"}        = "Nominal";
$bias{"83F010827"}          = 554;
$flat{"83F010827"}          = "";
$array{"83F010827"}         = "A";
$arraydir{"83F010827"}      = "/Volumes/ArrayA";

# ARRAY B CAMERAS

$model{"83F010692"}         = "STF-8300M";    
$location{"83F010692"}      = "NewMexicoSkies";
$nickname{"83F010692"}      = "A5";
$detector{"83F010692"}      = "KAF-8300ME";
$wheel{"83F010692"}         = "none";
$format{"83F010692"}        = "3326x2504";
$pixel_size{"83F010692"}    = "5.4,5.4";
$filters{"83F010692"}       =  "(SloanR)";   
$interface{"83F010692"}     = "USB";
$focuser_model{"83F010692"} = "birger";
$focuser_port{"83F010692"}  = "/dev/cu.USA49Wfa12P1.1";   # USB - Serial adapter A 
$focus_start{"83F010692"}   = 21720;
$host{"83F010692"}          = "XXX.XXX.XXX"; 
$lens{"83F010692"}          = "CanonEF400f2.8";
$status{"83F010692"}        = "Guider";  # Change from nominal if being used as a guider
$bias{"83F010692"}          = 732;
$flat{"83F010692"}          = "";
$array{"83F010692"}         = "B";
$arraydir{"83F010692"}      = "/Volumes/ArrayB";

$model{"83F010784"}         = "STF-8300M";
$location{"83F010784"}      = "NewMexicoSkies";
$nickname{"83F010784"}      = "B2";
$detector{"83F010784"}      = "KAF-8300ME";
$wheel{"83F010784"}         = "none";
$format{"83F010784"}        = "3326x2504";
$pixel_size{"83F010784"}    = "5.4,5.4";
$filters{"83F010784"}       =  "(SloanR)";   
$interface{"83F010784"}     = "USB";
$focuser_model{"83F010784"} = "birger";
$focuser_port{"83F010784"}  = "/dev/cu.USA49Wfa12P3.3";   # USB - Serial adapter B 
$focus_start{"83F010784"}   = 21880;
$host{"83F010784"}          = "XXX.XXX.XXX";
$lens{"83F010784"}          = "CanonEF400f2.8";
$status{"83F010784"}        = "Nominal";
$bias{"83F010784"}          = 743;
$flat{"83F010784"}          = "";
$array{"83F010784"}         = "B";
$arraydir{"83F010784"}      = "/Volumes/ArrayB";

$model{"83F010730"}         = "STF-8300M";                
$location{"83F010730"}      = "NewMexicoSkies";
$nickname{"83F010730"}      = "B3";
$detector{"83F010730"}      = "KAF-8300ME";
$wheel{"83F010730"}         = "none";
$format{"83F010730"}        = "3326x2504";
$pixel_size{"83F010730"}    = "5.4,5.4";
$filters{"83F010730"}       =  "(SloanR)";   
$interface{"83F010730"}     = "USB";
$focuser_model{"83F010730"} = "birger";
$focuser_port{"83F010730"}  = "/dev/cu.USA49Wfa12P4.4";   # USB - Serial adapter B 
$focus_start{"83F010730"}   = 21710;
$host{"83F010730"}          = "XXX.XXX.XXX";
$lens{"83F010730"}          = "CanonEF400f2.8";
$status{"83F010730"}        = "Nominal";
$bias{"83F010730"}          = 900;
$flat{"83F010730"}          = "";
$array{"83F010730"}         = "B";
$arraydir{"83F010730"}      = "/Volumes/ArrayB";

$model{"83F010826"}         = "STF-8300M";
$location{"83F010826"}      = "NewMexicoSkies";
$nickname{"83F010826"}      = "A4";
$detector{"83F010826"}      = "KAF-8300ME";
$wheel{"83F010826"}         = "none";
$format{"83F010826"}        = "3326x2504";
$pixel_size{"83F010826"}    = "5.4,5.4";
$filters{"83F010826"}       =  "(SloanR)";   
$interface{"83F010826"}     = "USB";
$focuser_model{"83F010826"} = "birger";
$focuser_port{"83F010826"}  = "/dev/cu.USA49Wfa12P2.2";   # USB - Serial adapter B 
$focus_start{"83F010826"}   = 22000;
$host{"83F010826"}          = "XXX.XXX.XXX";
$lens{"83F010826"}          = "CanonEF400f2.8";
$status{"83F010826"}        = "Nominal";   # Change to Nominal if not being used as a guider
$bias{"83F010826"}          = 922;
$flat{"83F010826"}          = "";
$array{"83F010826"}         = "B";
$arraydir{"83F010826"}      = "/Volumes/ArrayB";

# Focus functions
#
# Non-active cameras
$focusfunc{"311081163"}     = '"sub {my $x = shift; return(22196.04815*$x**0 + -3.220012976*$x**1 + 6.864098496e-06*$x**2 + -2.298420504e-05*$x**3)}"';
$focusfunc{"83F010612"}     = '"sub {my $x = shift; return(1880.233443*$x**0 + 6.6334773*$x**1 + -0.1687843963*$x**2 + 0.001358676308*$x**3)}"';
# COLD
# Active cameras on Camera Array A
#$focusfunc{"83F010783"}     = '"sub {my $x = shift; return(21750)}"';   # Determined at 27F
#$focusfunc{"83F010820"}     = '"sub {my $x = shift; return(21680)}"';   # Determined at 27F
#$focusfunc{"83F010827"}     = '"sub {my $x = shift; return(21730)}"';   # Determined at 27F
#$focusfunc{"83F010687"}     = '"sub {my $x = shift; return(21820)}"';   # Determined at 27F
## Active cameras on Camera Array B
#$focusfunc{"83F010826"}     = '"sub {my $x = shift; return(22000)}"';   # Determined at 26F
#$focusfunc{"83F010692"}     = '"sub {my $x = shift; return(21720)}"';   # Determined at 26F
#$focusfunc{"83F010784"}     = '"sub {my $x = shift; return(21880)}"';   # Determined at 26F
#$focusfunc{"83F010730"}     = '"sub {my $x = shift; return(21710)}"';   # Determined at 26F

#Warm
# Active cameras on Camera Array A
#$focusfunc{"83F010783"}     = '"sub {my $x = shift; return(21620 - 10.0*($x-50))}"';   # Determined at 50F
#$focusfunc{"83F010820"}     = '"sub {my $x = shift; return(21680 - 10.0*($x-50))}"';   # Determined at 50F
#$focusfunc{"83F010827"}     = '"sub {my $x = shift; return(21652 - 10.0*($x-54))}"';   # Determined at 54F 
#$focusfunc{"83F010687"}     = '"sub {my $x = shift; return(21763 - 10.0*($x-54))}"';   # Determined at 54F
# Active cameras on Camera Array B
#$focusfunc{"83F010826"}     = '"sub {my $x = shift; return(21978 - 10.0*($x-50))}"';   # Determined at 50F
#$focusfunc{"83F010692"}     = '"sub {my $x = shift; return(21676 - 10.0*($x-50))}"';   # Determined at 50F
#$focusfunc{"83F010784"}     = '"sub {my $x = shift; return(21700 - 10.0*($x-50))}"';   # Determined at 50F
#$focusfunc{"83F010730"}     = '"sub {my $x = shift; return(21658 - 10.0*($x-50))}"';   # Determined at 50F

#Hot
# Active cameras on Camera Array A
#$focusfunc{"83F010783"}     = '"sub {my $x = shift; return(21544 - 10.0*($x-71))}"';
#$focusfunc{"83F010820"}     = '"sub {my $x = shift; return(21500 - 10.0*($x-64))}"';
#$focusfunc{"83F010827"}     = '"sub {my $x = shift; return(21595 - 10.0*($x-71))}"';
#$focusfunc{"83F010687"}     = '"sub {my $x = shift; return(21679 - 10.0*($x-71))}"';
# Active cameras on Camera Array B
#$focusfunc{"83F010826"}     = '"sub {my $x = shift; return(21803 - 10.0*($x-71))}"';
#$focusfunc{"83F010692"}     = '"sub {my $x = shift; return(21613 - 10.0*($x-71))}"';
#$focusfunc{"83F010784"}     = '"sub {my $x = shift; return(21668 - 10.0*($x-71))}"';
#$focusfunc{"83F010730"}     = '"sub {my $x = shift; return(21573 - 10.0*($x-71))}"';

#General
# 
# Array A
$focusfunc{"83F010783"}     = '"sub {my $x = shift; return(21837.24719*$x**0 + -4.574949328*$x**1)}"';
$focusfunc{"83F010820"}     = '"sub {my $x = shift; return(21758.75567*$x**0 + -4.038428353*$x**1)}"';
$focusfunc{"83F010827"}     = '"sub {my $x = shift; return(21878.72485*$x**0 + -4.217356495*$x**1)}"';
$focusfunc{"83F010687"}     = '"sub {my $x = shift; return(21971.17362*$x**0 + -4.120736952*$x**1)}"';
# Array B
#$focusfunc{"83F010826"}     = '"sub {my $x = shift; return(22000 - 10.0*($x-39))}"';   # Needs tweaking
$focusfunc{"83F010826"}     = '"sub {my $x = shift; return(21800 - 10.0*($x-50))}"';   # Determined at 50F
$focusfunc{"83F010692"}     = '"sub {my $x = shift; return(21865.79983*$x**0 + -4.032170269*$x**1)}"';
$focusfunc{"83F010784"}     = '"sub {my $x = shift; return(21965.1617*$x**0 + -4.492252314*$x**1)}"';
$focusfunc{"83F010730"}     = '"sub {my $x = shift; return(21850.52401*$x**0 + -4.279887777*$x**1)}"';

# Check if all keys requested are defined, and if not, report which one is missing.
@trial_keys = keys %model;
$trial_key = pop(@trial_keys);
foreach(@ARGV) {
    $cmd = "defined(".'$'.$_."{\"$trial_key\"}".")";
    die "Unknown keyword $_" if !eval("$cmd");
}

# Return information. In the first case, the user wants the info for a specific camera, while in the
# second the user wants information for all cameras.
if (defined($camera)) {
    foreach(@ARGV) {
        $cmd = '$'.$_.'{$camera}';
        printf("%-15s", eval("$cmd"));
        print " ";
    }
    print "\n";
}
else {
    foreach $ccd (keys(%model)) {
        if ($location{$ccd} =~ /$location/i || $location =~ /any/i) {
            printf("%-9s ",$ccd);
            foreach(@ARGV) {
                $cmd = '$'.$_.'{$ccd}';
                printf("%-15s", eval("$cmd"));
                print " ";
            }
            print "\n";
        }
    }
}

__END__


=head1 NAME

camera_info - Obtain information on Project Dragonfly's hardware configuration.

=head1 USAGE

camera_info [options] [field1] ... [fieldN]

=head1 ARGUMENTS

=over 8

=item B<[field1] ... [fieldN]>

One or more keywords. If no keyword is suppled the serial number of the lenses is
printed as a special case. Execute 'camera_info --man' for a list of known keywords.

=back

=head1 OPTIONS

=over 8

=item B<--camera string>

Species the serial number of a specific camea for which information is
required. The default is to print information for all cameras.

=item B<--location string>

Specifies the location of the cameras of interest. The default is NewMexicoSkies. Currently
known locations are: NewMexicoSkies, Toronto, and InTransit.

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits. See this manual page for the list of known keywords.

=back

=head1 DESCRIPTION

B<camera_info> provides general information on the camera configuration of the Dragonfly array.
Cameras are always identified by their serial number. The following keywords are known:

B<array> - letter indicating which array the lens is attached to (e.g. A, B)

B<arraydir> - root directory for data access on the server machine (e.g. /Volumes/ArrayB)

B<bias> - typical bias level of the camera

B<detector> - detector model (e.g. KAF-8300ME)

B<filters> - filters available  e.g. "(SloanR)"

B<flat> - path to a good flat (e.g. /Users/dragonfly/Dropbox/src/cal/311081163_flat.fits)

B<focuser_model> - type of focuser hooked up to the camera (e.g. robofocus, birger)

B<focuser_port> - serial port the focuser is attached to (e.g. /dev/cu.USA49Wfd13P2.2)

B<focusfunc> - a perl function that takes a temperature argument and returns a setpoint.

B<focus_start> - reasonable generic starting position for the focuser in digital set point units (e.g. 22000)

B<format> - CCD format (e.g. 3326x2504, 765x510)

B<host> - internal network IP address of the machine to which the camera is attached (e.g. XXX.XXX.XXX170)

B<interface> - interface to the camera (e.g. USB, Ethernet)

B<lens> - model of the lens attached to the camera (e.g. CanonEF400f2.8, TEC140, GuiderKitLens)

B<model> - camera model (e.g. ST-8300M, STF-8300M, ST-i, ST-402me)

B<location> - present location of the camera (e.g. NewMexicoSkies, Toronto, NewHaven)

B<nickname> - common name for lens (e.g. A1, B3)

B<pixel_size> - pixel size in microns (e.g. 5.4,5.4 or 7.4,7.4)

B<wheel> - currently unused

=head1 SPECIAL CASES

Use location "Any" if you want information on all cameras at any location.

=head1 EXAMPLES

Calling B<camera_info> without any arguments returns the serial numbers of all known cameras. 
Note that several of these are test cameras or backup cameras. 

% camera_info
 83F010783 
 83F010826 
 83F010820 
 83F010784 
 83F010827 
 83F010730 
 83F010687 
 83F010692 

Additional information is obtained by supplying keywords to B<camera_info>. For example:

% camera_info location focuser_port
 83F010783 NewMexicoSkies  /dev/cu.USA49Wfd12P2.2 
 83F010826 NewMexicoSkies  /dev/cu.USA49Wfa12P2.2 
 83F010820 NewMexicoSkies  /dev/cu.USA49Wfd12P4.4 
 83F010784 NewMexicoSkies  /dev/cu.USA49Wfa12P3.3 
 83F010827 NewMexicoSkies  /dev/cu.USA49Wfd12P1.1 
 83F010730 NewMexicoSkies  /dev/cu.USA49Wfa12P4.4 
 83F010687 NewMexicoSkies  /dev/cu.USA49Wfd12P3.3 
 83F010692 NewMexicoSkies  /dev/cu.USA49Wfa12P1.1 

The default is to only print information on cameras located at NewMexicoSkies. However,
information on cameras located somewhere else can be obtained by specifying a different
location with the --location option. For exampke, here is information for the lenses 
located in Toronto:

% camera_info --location Toronto location focuser_port
 10384     Toronto         none            
 402c13    Toronto         /dev/cu.usa49w262p3.3 
 83F010612 Toronto         /dev/cu.USA19Hfa12P1.1 

For information on cameras located anywhere, use --location any:

$ camera_info --location any location focuser_port
 311081163 InTransit       /dev/cu.USA49Wfd13P2.2 
 83F010783 NewMexicoSkies  /dev/cu.USA49Wfd12P2.2 
 10384     Toronto         none            
 402c13    Toronto         /dev/cu.usa49w262p3.3 
 83F010826 NewMexicoSkies  /dev/cu.USA49Wfa12P2.2 
 83F010820 NewMexicoSkies  /dev/cu.USA49Wfd12P4.4 
 83F010612 Toronto         /dev/cu.USA19Hfa12P1.1 
 83F010784 NewMexicoSkies  /dev/cu.USA49Wfa12P3.3 
 83F010827 NewMexicoSkies  /dev/cu.USA49Wfd12P1.1 
 83F010730 NewMexicoSkies  /dev/cu.USA49Wfa12P4.4 
 83F010687 NewMexicoSkies  /dev/cu.USA49Wfd12P3.3 
 83F010692 NewMexicoSkies  /dev/cu.USA49Wfa12P1.1 

Information for a specific camera can be obtained using the --camera keyword:

% dragonfly$ camera_info --camera 83F010730 location focuser_port
NewMexicoSkies  /dev/cu.USA49Wfa12P4.4 

One especially interesting keyword is 'focusfunc', which is the focus function
defined for the current setup. This is a perl function that can be evaluated in
a script to determine the optimal focus position for the lens hooked up to a
camera at a given temperature. For example, in August 2013 the following
cubic function does a good job of describing the focus position for the lens
attached to the camera with serial number 83F010687:

% camera_info --camera  83F010687 focusfunc
 "sub {my $x = shift; return(21971.17362*$x**0 + -4.120736952*$x**1)}" 

=cut
