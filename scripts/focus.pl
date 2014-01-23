#!/opt/local/bin/perl

use Getopt::Long;
use Pod::Usage;
use DateTime;

# Set up the interrupt handling
$SIG{'INT' } = 'interrupt';  $SIG{'QUIT'} = 'interrupt';
$SIG{'HUP' } = 'interrupt';  $SIG{'TRAP'} = 'interrupt';
$SIG{'ABRT'} = 'interrupt';  $SIG{'STOP'} = 'interrupt';

# Parse command-line options
my $man = 0;
my $help = 0;
my $device = "/xs";
my $verbose = 0;
my $exptime = 3;
my $showplot = 0;
my $minobj = 5;
my $simple = 0;
my $robust = 0;
my $graph = 0;
my $force = 0;
my $guider = 0;
my $dark = 0;
my $mail = 1;

my $maximum_acceptable_fwhm = 4.0;
my $guider_lens_id = "83F010692";

$result = GetOptions(
    "range=i" => \$range,
    "nsample=i" => \$nsample,
    "device=s" => \$device,
    "minobj=i" => \$minobj,
    "exptime=f" => \$exptime,
    "dark!" => \$dark,
    "verbose!" => \$verbose,
    "simple!" => \$simple,
    "force!" => \$force,
    "mail!" => \$mail,
    "help|?" => \$help,
    "graph" => \$graph,
    "guider!" => \$guider,
     man=> \$man) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

# Parse arguments
my $narg = $#ARGV + 1;
pod2usage(2) if $narg > 1;

if ($narg == 1) {
    $mode = $ARGV[0];
}
else {
    $mode = "fine";
}

# Timing variables
my $movement_time = 0;
my $integration_time = 0;
my $sextraction_time = 0;
my $total_time = 0;
$global_start_time = DateTime->now();

# Don't do a focus run if the roof is closed at any point during the focus run.
# We check at the start and at the end. If for some reason the status of the
# roof is unknown wait a few seconds and try again. In the event it is still
# unknown, then assume it is open.
if (!$force) {
    print "Determining position of the observatory roof.\n" if $verbose;
    $roof = `nms_roof_status`;
    if ($roof =~ /Unknown/){
        sleep 5;
        $roof = `nms_roof_status`; 
    }
    $roof = "Open" if ($roof =~ /Unknown/);     # Force the situation
    if ($roof =~ /Closed/) {
        print "Focus run aborted because the roof is closed at the start of run.\n";
        exit(1);
    }
}

# Determine the IP address of this machine
$my_ip = `ifconfig | grep "inet XXX.XXX" | awk '{print \$2}'`;
chop($my_ip);

# Settings below are appropriate for a Canon EF 400/2.8 IS II lens
if ($mode =~ /^coarse/i) {
    $range = 390 if !defined($range);
    $nsample = 14 if !defined($nsample);
    goto SETTINGS_DEFINED;
}

if ($mode =~ /^fine/i) {
    $range = 100 if !defined($range);
    $nsample = 10 if !defined($nsample);
    goto SETTINGS_DEFINED;
}

if ($mode =~ /^superfine/i) {
    $range = 30 if !defined($range);
    $nsample = 3 if !defined($nsample);
    $simple = 1; # This one has to be simple as we can't fit a proper parabola
    goto SETTINGS_DEFINED;
}

if ($mode =~ /^test/i) {
    $range = 30 if !defined($range);
    $nsample = 5 if !defined($nsample);
    goto SETTINGS_DEFINED;
}

die "Error: Unknown focus settings requested";

SETTINGS_DEFINED:

# Define the basic characteristics of the cameras
$cameras = `camera_info model lens focuser_port array host location status | grep NewMexicoSkies | grep Nominal | grep CanonEF400 | grep $my_ip`;
if ($guider) {
    `guider disconnect`;
    $cameras = `camera_info model lens focuser_port array host location | grep NewMexicoSkies | grep CanonEF400 | grep $guider_lens_id`;
}

for (split /^/, $cameras) {
    chop;
    @data = split;
    $serial_number = $data[0];
    $model{$serial_number} = $data[1];
    $lens{$serial_number} = $data[2];
    $focuser_port{$serial_number} = $data[3];
    $array{$serial_number} = $data[4];

    # Define a correction factor on the stepsize to account for the
    # fact that the 400mm cameras have a much finer action than
    # the 200mm lenses do. In general this correction is unity.
    $lenscorr{$serial_number} = 1.0;
    $lenscorr{$serial_number} = 0.25 if $lens{$serial_number} =~ /CanonEF200/;

}
my @cameras = keys(%focuser_port);

print STDERR "Focusing lenses attached to these cameras: @cameras \n";

# Determine the starting point for each focuser. We also determine here
# if a focuser is responding to commands.
print "Determining starting positions for cameras\n";
$start_time = DateTime->now();
my @working_cameras = ();
$step_size = int($range/$nsample);
foreach(@cameras) {
    $worked = 0;
    $niter = 0;
    while ($worked == 0 && $niter < 3) {
        $original_position{$_} = `birger_client $_`;
        $current_position{$_} = $original_position{$_};
        chop($current_position{$_});
        if ($current_position{$_}=="") {
            $niter++;
            print "STDERR *** Cannot talk to focuser on CCD $_ ***" if ($niter > 3);
        }
        else {
            $working_cameras[++$#working_array] = $_;
            $worked = 1;
            printf(STDERR "Intial position for focuser on CCD $_: %d\n",$current_position{$_});
            $starting_position{$_} = $current_position{$_} - int($lenscorr{$_}*$nsample/2)*$step_size; 
            $best_seeing{$_} = 1e30;
            $best_index{$_} = -1;
            $best_position{$_} = $current_position{$_};
            $worst_seeing{$_} = 0.0;
        }
    }
}
$movement_time += report_timing($start_time,$verbose);


# We need to be careful to ensure other programs know when this thing is
# running. We will handle this using a lock file.
$mylockfile = "/var/tmp/focus.lock";
`rm -f $mylockfile`;
open(MYLOCKFILE, ">>$mylockfile") || die;
flock(MYLOCKFILE, 2) || die;
print MYLOCKFILE "Autofocus run in progress\n";
print MYLOCKFILE "Data taking started at ",scalar(localtime),"\n";

for (my $count = -1; $count < $nsample; $count++) {

    # Take a snapshot of the FITS files in this directory
    `ls -1 *.fits > /var/tmp/before.txt 2> /dev/null`;

    # Obtain new data... one dark frame followed by a user-specified
    # number of light frames.
    if ($count == -1) {
        if ($dark) {
            print STDERR "Taking dark frames\n";
            system("expose dark $exptime");
        }else{
            next; 
        }
    }
    else {

        printf(STDERR "\nIteration %d of %d: \n", $count + 1, $nsample);

        # Drive each focuser to a new position
        print "Driving focuser to new position\n";
        $start_time = DateTime->now();
        foreach(@working_cameras) {

            $niter = 0;
            $worked = 0;
            while ($worked == 0 && $niter < 3 ) {

                $niter++;
 
                # Drive focuser to the new position
                my $desired_position = $starting_position{$_} + int($lenscorr{$_}*$count*$step_size);
                printf(STDERR "  Commanding focuser $_ to go to %d\n",$desired_position);
                `birger_client $_ goto $desired_position`;

                # Did it work?
                $current_position{$_} = `birger_client $_`;
                chop($current_position{$_});
                printf(STDERR "  Focuser $_ reports it is at %d\n",$current_position{$_});
                $check = abs($desired_position - $current_position{$_});
                if ($check < 5) {
                    $worked = 1;
                    print STDERR "  Succeeded\n";
                }
                else {
                    if ($niter > 3) {
                        print STDERR "Giving up... apparently we have a loss of focuser control" if ($niter > 3);
                        `syslog -s -l alert [DragonflyError] Focuser $_ is not working`;
                        `mutt -s "NOTIFICATION: focuser $_ is not working!" projectdragonfly\@icloud.com < /dev/null`;
                        last;
                    }
                    print STDERR "  Focuser did not wind up at the desired position. Trying another time...\n";
                }

            }

        }
        $movement_time += report_timing($start_time,$verbose);

        # Focus movement succeeded. Take a data frame.
        print "Integrating\n";
        $start_time = DateTime->now();
        system("expose light $exptime");
        $integration_time += report_timing($start_time,$verbose);
    }

    # Figure out which FITS files have just been created
    `ls -1 *.fits > /var/tmp/after.txt`;
    $new_files = `diff /var/tmp/before.txt /var/tmp/after.txt  | grep ">" | awk '{print \$2}'`;
    chop($new_files);
    @new_files = split(/\n/,$new_files);
    print "Files to process: @new_files\n" if $verbose;

    # ANALYZE EACH NEW FRAME

    print "Source extracting new frames\n";
    $start_time = DateTime->now();
    foreach (@new_files)
    {
        $file = $_;
        $original_file = $file;

        # Extract serial number which will be used as a key to allow this to work
        # with multiple cameras.
        $file =~ /(^.+)(_.+)(_.+)/;
        $serial_number = $1;
        $serial_number =~ s/^\.\///g; # nuke preceding ./

        if ($count == -1) {

            # The first set of files are all dark frames
            
            # Nuke the dark frame if it corresponds to a camera with no focuser
            if ($focuser_port{$serial_number} !~ /dev/) {
                `rm $original_file`;
                 next;
            }

            # Record the names of the dark frames for cameras with focusers in a hash
            $darkfile{$serial_number} = $file;

        }

        else {

            # Nuke the file if it corresponds to a camera with no focuser
            if ($lens{$serial_number} !~ /CanonEF/) {
                print STDERR "Deleting $original_file as it does not correspond to a camera with a Birger focuser\n";
                `rm $original_file`;
                next;
            }

            # If camera has a focuser analyze the data
            $dsfile = "focus_" . $serial_number . "_" . $current_position{$serial_number} . ".fits";
            if ($dark) {
                print STDERR "Dark subtracting $file\n";
                `imcalc -o $dsfile "%1 %2 -" $file $darkfile{$serial_number}`;
                `modhead $file FOCUS $current_positon{$serial_number}`;
                `modhead $dsfile FOCUS $current_positon{$serial_number}`;
                print(STDERR "Dark subtracted data stored in $dsfile.\n");
            }
            else{
                `cp $file $dsfile`;
            }

            print(STDERR "Source extracting...\n");
            $seeing_data = `extract -s $dsfile | tfilter 'FLAGS==0 && FWHM_IMAGE>0' | tcolumn FWHM_IMAGE | rstats c e s`;
            $seeing_data =~ s/^\s+//g;
            chop($seeing_data);
            ($nobj,$seeing,$sigma) = split(/\s+/,$seeing_data);
            $seeing = 999. if $seeing =~ /nan/;
            $seeing = 999. if $nobj < $minobj;
            if ($seeing < 999) {
                $sigma = 2.0*$sigma/sqrt($nobj-1);
                printf(STDERR "Seeing computed: %5.2f +/- %5.2f pix based on %d stars.\n",$seeing,$sigma,$nobj);
            }
            else {
                print(STDERR "Insufficient number of stars detected.\n");
            }
            $position = $current_position{$serial_number};

            # Index everything according to the serial number of the camera. 
            $position{$serial_number}[$count]  = $position;
            $seeing{$serial_number}[$count]    = $seeing;
            $sigma{$serial_number}[$count]     = $sigma;
            $nobj{$serial_number}[$count]      = $nobj;

            `rm $dsfile`;
            `rm $original_file`;

        }
    }
    $sextraction_time += report_timing($start_time,$verbose);
}

# Remove dark frames
if ($dark) {
    foreach $camera (@working_cameras) {
        `rm $darkfile{$camera}`;
    }
}

# Before doing anything further restore the focusers to their original
# positions. That way, if anything goes wrong below, we're left at a
# sensible non-crazy position.
print "Restoring original positions\n";
$start_time = DateTime->now();
foreach $camera (@working_cameras) {
    `birger_client $camera goto $original_position{$camera}`;
}
$movement_time += report_timing($start_time,$verbose);

# Make sure the roof is still open... if not, leave things unchanged as we may
# not have enough data to determine the correct focus position.  If for some
# reason the status of the roof is unknown wait a few seconds and try again. In
# the event it is still unknown, then assume it is open.
print "Determining position of the observatory roof.\n" if $verbose;
$roof = `nms_roof_status`;
if ($roof =~ /Unknown/){
    sleep 5;
    $roof = `nms_roof_status`;
}
$roof = "Open" if ($roof =~ /Unknown/); 
if ($roof =~ /Closed/ && !$force) {
    print "Focus run aborted because roof is closed at the end of the run.\n";
    close(MYLOCKFILE);
    `rm -f $mylockfile`;
    exit(1);
}


##### ANALYZE DATA #####

#First figure out the number of # unique cameras we have data for.
my %seen;
my @working_cameras = grep { not $seen{$_} ++ } @working_cameras;
print STDERR "Data found for these cameras: @working_cameras\n";


# Figure out the results for each camera

print MYLOCKFILE "Data taking completed. Results being analyzed.\n";
print STDERR "\n";
print STDERR "============================================================\n";
print STDERR "      Data taking completed. Now analyzing results.\n";
print STDERR "============================================================\n";
print STDERR "\n";


$localtime = `date`; chop($localtime);
$universaltime = `date -u`; chop($universaltime);
print STDERR "Obtaining temperature information\n";
$nms = `curl -s www.newmexicoskies.com/weather1.txt`;
@weatherdata = split(',',$nms);
$temperature = $weatherdata[0];
$dewpoint = $weatherdata[1];
$humidity = $weatherdata[2];
$windspeed = $weatherdata[3];
$gusts = $weatherdata[4];
$sunset = $weatherdata[5];
$sunrise = $weatherdata[6];
$rain = $weatherdata[7];
$wind = $weatherdata[8];
$fog = $weatherdata[9];
$pod1 = $weatherdata[10];
$pod2 = $weatherdata[11];

`rm -f AUTOFOCUS_SOLUTION.txt`;
$result_file = "AUTOFOCUS_SOLUTION.txt";
open(RESULTS,">$result_file");
print RESULTS "local:         $localtime\n";
print RESULTS "universal:     $universaltime\n";
print RESULTS "temperature:   $temperature\n";
print RESULTS "dewpoint:      $dewpoint\n";
print RESULTS "humidity:      $humidity\n";
print RESULTS "windspeed:     $windspeed\n";
print RESULTS "gusts:         $gusts\n";
$arrayname = "(array $array{$working_cameras[0]}; resolution $mode)";
$mailstring = "mutt -s \"Focus results $arrayname\" ";
$mailstring = "mutt -s \"Focus results (guider)\" " if $guider;


foreach $camera (@working_cameras) {

    print STDERR "\n";
    print STDERR "Analyzing data for camera with serial number $camera\n";

    # Print a global summary to a temporary file (in SExtractor table format).
    `rm /var/tmp/focusrun_$camera.txt`;
    $ngood = 0;
    print STDERR "Data saved to /var/tmp/focusrun_$camera.txt\n";
    open(FOCUSRUN,">/var/tmp/focusrun_$camera.txt");
    print FOCUSRUN "# 1  POSITION     Focuser position \n";
    print FOCUSRUN "# 2  FWHM         Full-width at half-maximum [pixel]\n";
    print FOCUSRUN "# 3  FWHM_SIGMA   Standard deviation of FWHM [pixel]\n";
    print FOCUSRUN "# 4  NOBJECTS     Number of objects used to compute FWHM\n";

    $min_seeing{$camera} = 999;
    $min_figure_of_merit{$camera} = 999;
    for ($i=0;$i<$nsample;$i++) {
        if ($seeing{$camera}[$i] > 0.01 && $seeing{$camera}[$i] < 999) {
            $ngood++;
            if ($seeing{$camera}[$i] < $min_seeing{$camera}){
                $min_seeing{$camera} = $seeing{$camera}[$i];
                $min_position{$camera} = $position{$camera}[$i];
            }
            #if (($seeing{$camera}[$i] * $sigma{$camera}[$i]) < $min_figure_of_merit{$camera}){
            if (($seeing{$camera}[$i]) < $min_figure_of_merit{$camera}){
                $min_figure_of_merit{$camera} = $seeing{$camera}[$i];
                #$min_figure_of_merit{$camera} = $seeing{$camera}[$i] * $sigma{$camera}[$i];
                $min_figure_of_merit_position{$camera} = $position{$camera}[$i];
            }
             printf(FOCUSRUN "%10d %6.2f %6.2f  %d\n",
                $position{$camera}[$i],$seeing{$camera}[$i],$sigma{$camera}[$i],$nobj{$camera}[$i]);
        }
    }
    close(FOCUSRUN);
    printf("Minimum at %8d (FWHM = %5.2f)\n",$min_position{$camera},$min_seeing{$camera});

    if ($ngood >= 3) {

        # Fit data to a parabola
        $par = `tfitpoly -n 2 POSITION FWHM FWHM_SIGMA < /var/tmp/focusrun_$camera.txt`;
        chop($par);
        ($a,$b,$c) = split(/\s+/,$par);
        $min_parabola = -$b/(2.0*$c);
        if ($c >= 0.0) {
            $best_seeing = $a + $b*$min_parabola + $c*($min_parabola**2);
            $new_setpoint = int($min_parabola + 0.5);
            printf(STDERR "Parabolic fit results: minimum at %8.2f (FWHM = %5.2f)\n",$min_parabola,$best_seeing);
        }
        else {
            # Focus run produced a dubious result - parabola pointing in the wrong direction. Override!
            $best_seeing = $min_seeing{$camera};
            $new_setpoint = $min_position{$camera};
            printf(STDERR "Parabola is inverted. Tossing this result and going with the position at minimum value instead.\n");
        }

        $title = sprintf("Camera: $camera. Best focus position: %d (FWHM = %.2f pix)",$new_setpoint,$best_seeing); 
        $pngfile{$camera} = "AUTOFOCUS_PLOT_" . $camera . ".png";
        $device = "$pngfile{$camera}/png";
        if ($simple) {
            #$title = sprintf("Camera $camera. Minimum of FWHM x RMS at: %d (FWHM = %.2f pix)",$min_figure_of_merit_position{$camera},$min_seeing{$camera}); 
            $title = sprintf("Camera $camera. Minimum FWHM at: %d (FWHM = %.2f pix)",$min_figure_of_merit_position{$camera},$min_seeing{$camera}); 
            `tplot --dev $device --xformat 1 --title "$title" --vline $min_figure_of_merit_position{$camera} POSITION FWHM FWHM_SIGMA < /var/tmp/focusrun_$camera.txt`;
        } else {
            `tplot --dev $device --xformat 1 --parabola $par --title "$title" --vline $min_parabola POSITION FWHM FWHM_SIGMA < /var/tmp/focusrun_$camera.txt`;
        }
        print STDERR "Graphical results stored in $pngfile{$camera}\n";
        print STDERR "View using \'open $pngfile{$camera}\' or \'open *.png\'\n";
        `open $pngfile{$camera}` if $graph;

        # If the seeing is better than the worst acceptable seeing, bless the camera
        if ($best_seeing < $maximum_acceptable_fwhm) {
            print "Blessing $camera\n";
            `df_send focusers "$camera bless"`;
        }
        else {
            print "Cursing $camera\n";
            `df_send focusers "$camera curse"`;
        }

        # Drive system to best focus 
        $niter = 0;
        $worked = 0;

        print "Driving focuser to final position\n";
        $start_time = DateTime->now();
        while ($worked == 0 && $niter < 3 ) {

            $niter++;
            if (!$simple && $best_seeing > 1.0 && $best_seeing < 6.0) {
                printf(STDERR "Best seeing is %.2f\n",$best_seeing);
                printf(STDERR ">>>> Setting focuser $camera to: %d <<<<\n",$new_setpoint);
            }
            else {
                printf(STDERR "******** PLAYING IT SAFE AND USING THE POSITION AT THE MINIMUM SEEING X RMS VALUE TO DEFINE THE SETPOINT! ********* \n");
                $new_setpoint = $min_figure_of_merit_position{$camera};
                $best_seeing = $min_seeing{$camera};
            }
            `birger_client $camera goto $new_setpoint`;

            # Did it work?
            $current_position = `birger_client $camera`;
            chop($current_position);
            printf(STDERR "  Focuser $camera reports it is at %d\n",$current_position);
            $check = abs($new_setpoint - $current_position);
            if ($check < 5) {
                $worked = 1;
                print STDERR "  Succeeded\n";
            }
            else {
                if ($niter > 3) {
                    print STDERR "Giving up... apparently we have a loss of focuser control" if ($niter > 3);
                    `mutt -s "NOTIFICATION: focuser $_ is not working!" projectdragonfly\@icloud.com < /dev/null`;
                    last;
                }
                print STDERR "  Focuser did not wind up at the desired position. Trying another time...\n";
            }
        }
        $movement_time += report_timing($start_time,$verbose);

        # Save current setpoint and anicillary environmental information to an individual text file
        # $result_file = "AUTOFOCUS_SOLUTION_" . $camera. ".txt";
        # open(STATUS,">$result_file");
        # print STATUS "time: ",localtime,"\n";
        # print STATUS "camera: ",$camera,"\n";
        # print STATUS "setpoint: ",$new_setpoint,"\n";
        # close(STATUS);

        # Save data to a separate text file which holds data for everything
        $best_seeing = sprintf("%.2f",$best_seeing);
        $min_seeing{$camera} = sprintf("%.2f",$min_seeing{$camera});
        print RESULTS "---------------------------\n";
        print RESULTS "camera:     $camera\n";
        print RESULTS "setpoint:   $new_setpoint\n";
        print RESULTS "fit_seeing: $best_seeing\n";
        print RESULTS "min_seeing: $min_seeing{$camera}\n";

        $mailstring = $mailstring . "-a $pngfile{$camera} ";

    }
    else {
        `df_send focusers "$camera curse"`;
        print STDERR "Insufficient number of data points for camera $camera \n";
    }
}

$total_time += report_timing($global_start_time,$verbose);

print RESULTS "\n";
print RESULTS "---------------------------\n";
print RESULTS "OVERHEADS\n";
print RESULTS "---------------------------\n";
printf(RESULTS "Movement time:    %3d\n",$movement_time);
printf(RESULTS "Integration time: %3d\n",$integration_time);
printf(RESULTS "SExtraction time: %3d\n",$sextraction_time);
printf(RESULTS "Total time:       %3d\n",$total_time);
close(RESULTS);

# We are done. Clean up the lock file. Note that closing the file frees the lock,
# but we will nuke the lockfile so that any program that wants to see at a glance
# if this program is running can simply check for the existence of the lockfile.
close(MYLOCKFILE);
`rm -f $mylockfile`;

# Optionally send the user a report on how things went
if ($mail) {
    $mailstring = $mailstring . "projectdragonfly\@icloud.com < $result_file";
    print "E-mailing the results via this command:\n$mailstring\n";
    `$mailstring`;
}


# Handle interrupts by aborting the exposure, restoring original focus position, and exiting
sub interrupt {
     my($signal)=@_;
     print "Caught Interrupt\: $signal \n";
     print "Checking to see if integrations are in progress.\n";
     # Figure out if an exposure is in progress and if so cancel it.
     open(PROC,"ps -ef | awk '{print \$2,\$8}'| grep expose |");
     if ($ps_line = <PROC>){
         # get process ID
         ($pid,$junk)=split('\s+',$ps_line);
         # send an interrupt to the process
         kill 2, $pid;
         print $connection "Integration aborted on all connected cameras.\n";
     }
     else {
         print "No integrations need to be aborted.\n";
     }
     close(PROC);
     # Close the lockfile so other processes know what is going on
     close(MYLOCKFILE);
     `rm -f $mylockfile`;
     # Restore original positions.
     print "Restoring original focus positions\n";
     foreach $camera (@working_cameras) {
         `birger_client $camera goto $original_position{$camera}`;
     }
     print "Focus run has been aborted cleanly.\n";
     exit(1);
} 

sub report_timing {
    my $start_time = shift;
    my $verbose = shift;
    my $end_time = DateTime->now();
    my $elapsed_time = ($end_time->subtract_datetime_absolute($start_time))->in_units('seconds');
    print "  Done (took $elapsed_time seconds).\n" if ($verbose);
    return($elapsed_time);
}

##########################################################################


__END__

=head1 NAME

focus - Set the best focus position for a bank of CCD cameras

=head1 SYNOPSIS

focus [options] [coarse|fine|superfine]

options:

 -range number
 -nsample number
 -exptime number
 -simple
 -graph
 -device string
 -verbose
 -minobj
 -force
 -help
 -man

=head1 ARGUMENTS

=over 8

=item B<coarse|fine|superfine>

Operational mode for the focuser. Coarse mode has a range of 300 steps with
sampling at 10 positions. Fine mode has a range of 100 steps with sampling at
10 positions. Superfine mode has a range of 30 steps with sampling at 10 positions.
These ranges and sampling values can be overridden using the -range and
-nsample command-line arguments. The default is "coarse".

=back

=head1 OPTIONS

=over 8

=item B<-range number>

Range in steps (centered on the current positon) over which to look for the best focus.
In other words, the focuser looks for the best focus within this range: 
(current position - range/2, current position + range/2).

=item B<-nsample number>

Number of positions to sample within the focus range.

=item B<-exptime number>

Integration time in seconds (default is 3).

=item B<-device string>

PGPLOT device to use for the plot. The default is "/xs". 

=item B<-simple>

If this switch is set then the algorithm "plays it safe" and uses the position
of the minimum value of the seeing as the setpoint. This makes sense in cases
where you are starting off very far from focus and fitting to a parabola 
may not make sense.

=item B<-force>

Force the script to run even if the roof is closed. (Useful for testing).

=item B<-graph>

Display results graphically. If this is not selected the graphical
results are still saved in PNG files but the PNG files are not displayed. This allows
the routine to be used over a network connection. The default is to not
display graphics.

=item B<-minobj>

Minimum number of objects on a frame before the FWHM is computed. If fewer than minobj objects exist on
a frame then the data is dropped from further consideration. This is useful because when data is
very far from focus a few insanely bogus detections can occur which result in crazy
FWHM values. The default is 5.

=item B<-verbose>

Print informational messages.

=item B<-help>

Print a brief help message and exit.

=item B<-man>

Print the manual page and exit.

=back

=head1 DESCRIPTION

B<focus> performs a series of integrations at a range of focus settings and
concludes by leaving the focuser set to the best focus position. The best focus
position is determined in one of two ways:

1. The position that which results in the minimum FWHM (determined by
the "seeing" program, which uses SExtractor to estimate the FWHM).

2.  The position is determined by parabolic interpolation. 

Parabolic interpolation is the default method and the minimum FWHM is only
used if the parabola is obviously crazy (e.g. it points in the wrong direction).

The best-fit solution is illustrated using a diagram which plots the seeing 
FWHM as a function of focus position.

If the roof is closed (or its position is unknown) either at the start or
the end of the focus run, then the cameras are left in their original state
and no focus change is applied.

If B<focus> is aborted with an interrupt, then integrations are aborted 
on all cameras and the focusers are returned to their original states before
B<focus> exits.

=cut
