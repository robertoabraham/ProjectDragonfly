#!/opt/local/bin/perl

use Getopt::Long;
use Pod::Usage;
use Term::ProgressBar;
use DateTime;

# Startup options
$| = 1;

# Globals
$pi = 3.14159;

# Parse command-line options
my $niter=9;                  # number of steps in the sequence
my $exptime = 600;            # exposure time in seconds
my $dither_angle = 25.0;      # dither angle in arcmin
my $host = "XXX.XXX.XXX.XXX";
my $port = 3040;
my $verbose = 1;
my $guide = 1;
my $tweak = 1;
my $man = 0;
my $help = 0;
my $focus = 1;
my $dark = 1;
my $debug = 0;
my $backlash_compensation = 5;

$help = 1 if $#ARGV == -1;
$result = GetOptions(
    "niter=i"=>\$niter,
    "exptime=f"=>\$exptime,
    "dangle=f" => \$dither_angle,
    "focus!" => \$focus,
    "guide!" => \$guide,
    "dark!" => \$dark,
    "debug+" => \$debug,
    "tweakfocus!" =>\$tweak,
    "host=s" => \$host,
    "port=i" => \$port,
    "verbose!" => \$verbose,
    "help|?" => \$help, 
     man=> \$man) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

# Parse arguments
$target = $ARGV[0];
$narg = $#ARGV + 1;
$target = "'" . $target . "'" if ($target=~/ /);
pod2usage(2) if $narg != 1;

# Determine the name of the subdirectory where the data will be stored
chomp($tonightdir=`df_send cameras pwd | head -1 | awk '{print \$4}' | sed 's/\\/Users\\/dragonfly\\/Data\\///g'`);
print "Data being stored in: $tonightdir\n";

# Set up the interrupt handling
$exit_asap = 0;
$SIG{'INT' } = 'interrupt';  $SIG{'QUIT'} = 'interrupt';
$SIG{'HUP' } = 'interrupt';  $SIG{'TRAP'} = 'interrupt';
$SIG{'ABRT'} = 'interrupt';  $SIG{'STOP'} = 'interrupt';

# Upload a JPG image to the server showing the all-sky camera view of the end of the sequence
print "Uploading all-sky image to the data server\n";
`upload_all_sky_image start_sky.jpg`;

# Time stamps
`syslog -s -l alert [DragonflyStatus] auto_observe begun. Target is $target. Data will be stored in $tonightdir.`;
$start = `date`;
print "Starting at $start" if $verbose;

############# Execute the observations. ##########

#@dither_position_angle = ("",0,45,90,135,180,225,270,315);
@dither_position_angle = (315,0,45,270,90,225,135,180,"");
$n_target = 0;
$n_guided = 0;
$plan_b = 0;
$currently_guiding = 0;
$temperature = 'Unknown';
$has_flipped = 0;

# Variables which track the overheads
my $slew_time = 0;
my $dither_time = 0;
my $focus_time = 0;
my $guider_setup_time = 0;
my $readout_time = 0;
my $science_time = 0;
my $store_metadata_time = 0;
my $dark_time = 0;

# Connect the autoguider
`guider connect` if $guide;

for($iteration=0;$iteration<$niter;$iteration++) {

    # If the INTERRUPT.txt file exists, bail out. This gives the user a chance to bail out without sending a ^C.
    # This doesn't delete the INTERRUPT.txt file so the next auto_observe will not happen either.
    &check_for_interrupt_file($currently_guiding);

    # If the NEXT_TARGET.txt file exists, bail out. This gives the user a chance to bail out without sending a ^C.
    # This deletes the NEXT_TARGET.txt file so the next auto_observe will be initiated.
    &check_for_next_target_file($currently_guiding);

    # If it is time for morning flats then bail out.
    chomp($action = `almanac | grep SuggestedAction | awk '{print \$2}'`);
    if ($action =~ /MorningFlat/) {
        `syslog -s -l alert [DragonflyStatus] Ending auto_observe because the time for morning flats has arrived.`; 
        die "Ending auto_observe because it is now time for for morning flats\n";
    }

    printf("\nObtaining target data. Iteration %d\n",$iteration+1);
    # Time stamps
    $logmessage = sprintf("auto_observe - iteration %d begun.",$iteration+1);
    `syslog -s -l alert [DragonflyStatus] $logmessage`;

    # Make sure the scope is tracking
    print "  Start tracking\n" if $verbose;
    $start_time = DateTime->now();
    $mount_start_command = "mount --host $host start";
    print "    Mount command issued to start tracking: $mount_start_command\n" if ($verbose);
    `syslog -s -l alert [DragonflyStatus] auto_observe - start tracking.`;
    `$mount_start_command`;
    $slew_time += report_timing($start_time,$verbose);

    # Slew to the target
    print "  Slewing to $target\n" if $verbose;
    $start_time = DateTime->now();
    $slew_command = "mount --host $host goto $target";
    print "    Mount command issued to slew: $slew_command\n" if ($verbose);
    `syslog -s -l alert [DragonflyStatus] auto_observe - slewing.`;
    `$slew_command`;
    `syslog -s -l alert [DragonflyStatus] auto_observe - slew complete.`;
    $slew_time += report_timing($start_time,$verbose);

    # Determine current mount azimuth
    print "  Determining mount azimuth for anti-backlash compensation move \n" if $verbose;
    $start_time = DateTime->now();
    $position_command = "mount --host $host position";
    print "    Mount command issued: $position_command\n" if ($verbose);
    `syslog -s -l alert [DragonflyStatus] auto_observe - obtaining azimuth.`;
    $mountdata = `$position_command`;
    $slew_time += report_timing($start_time,$verbose);
    if (!$mountdata || $mountdata =~ /^Error/) {
	    `syslog -s -l alert [DragonflyError] auto_observe - azimuth unknown.`;
	    printf(STDERR "Error communicating with the mount.\n");
    }
    else {
	    chop($mountdata);
	    ($ra,$dec,$alt,$az,$otaside) = split(/\s+/,$mountdata);
	    $dec =~ s/\*/d/g;
	    print "  Mount position: $mountdata.\n" if $verbose;
	    print "  Azimuth: $az.\n" if $verbose;
	    `syslog -s -l alert [DragonflyStatus] auto_observe - azimuth obtained.`;
    }
    # Determine sign of anti-backlash correction move and make the appropriate
    # change in quadrants. Although experience seems to show the same move in all
    # quadrants works best...
    if($az >= 0.0 && $az < 90.0) { 
	    $anti_backlash_move = $backlash_compensation;
    }
    elsif($az >= 90.0 && $az < 180.0) { 
	    $anti_backlash_move = $backlash_compensation;
    }
    elsif($az >= 180.0 && $az < 270.0) { 
	    $anti_backlash_move = $backlash_compensation;
    }
    else {
	    $anti_backlash_move = $backlash_compensation;
    }

    # Do a focus run if needed
    if (!(-e "FOCUS_RUN_COMPLETED.txt") || $iteration == 0 || (-e "FOCUS_NOW.txt")) {
        if ($focus) {
            $start_time = DateTime->now();
            print "  Initiating a focus run.\n" if ($verbose);
            $focus_command = "all_focus";
            print "  Focus command issued: $focus_command\n" if ($verbose);
            `$focus_command` if ($focus);
            $focus_time += report_timing($start_time,$verbose);
            `rm -f FOCUS_NOW.txt`;
        }
    }
 
    # Do a small dither shift if needed. This automatically takes care of meridian flips.
    if (length($dither_position_angle[$iteration]) > 0) {
        print "  Dithering about the target\n" if $verbose;
        $start_time = DateTime->now();
        $north = $dither_angle*sin(($pi/180.0)*$dither_position_angle[$iteration]);
        $west  = $dither_angle*cos(($pi/180.0)*$dither_position_angle[$iteration]);
        $north = sprintf("%7.2f",$north);
        $west = sprintf("%7.2f",$west);
        $start_time = DateTime->now();
        $dither_command = "mount --host $host dither $north N";
        print "    Mount command issued to dither: $dither_command\n";
        `syslog -s -l alert [DragonflyStatus] auto_observe - dithering.`;
        `$dither_command`;
        `syslog -s -l alert [DragonflyStatus] auto_observe - dither complete.`;
        if ($?) {
            print "      Error occurred sending dither message to mount. This usually completes successfully anyway.\n";
            print "      Ignore error message and press on.\n";
        }
        $dither_command = "mount --host $host dither $west W";
        print "    Mount command issued to dither: $dither_command\n";
        `$dither_command`;
        if ($?) {
            print "      Error occurred sending dither message to mount. This usually completes successfully anyway.\n";
            print "      Ignore error message and press on.\n";
        }
        $dither_time += report_timing($start_time,$verbose);
    }
    else {
        print "  No dither needed.\n";
    }

    # Anti-backlash
    $start_time = DateTime->now();
    $dither_command = "mount --host $host dither $anti_backlash_move N";
    print "  Declination backlash compensation. Mount command issued: $dither_command\n";
    `$dither_command`;
    if ($?) {
        print "      Error occurred sending dither message to mount. This usually completes successfully anyway.\n";
        print "      Ignore error message and press on.\n";
    }
    $dither_time += report_timing($start_time,$verbose);

    # Move focus position to compensate for changes in temperature.
    $last_temperature = $temperature;
    chomp($temperature = `nms_temperature`);
    if (!$? && $temperature !~ /Unknown/ && $last_temperature !~ /Unknown/ && $temperature > 0 && $temperature < 200) {
        printf("  Current Temperature: %d F\n",$temperature);
        my $delta_temperature = $temperature - $last_temperature;
        my $delta_setpoint = -4.5 * $delta_temperature;
        printf("  Temperature has changed by %d F since last iteration\n",$delta_temperature);
        if ($delta_setpoint != 0) {
            printf("  Moving all focusers by %d digital setpoints to compensate\n",$delta_setpoint);
            `all_change_focus -- $delta_setpoint`;  # The -- is to stop negative moves from being parsed as options
            if ($?) {
                print "  Error changing focus\n";
            }
            else {
                print "  Focus adjusted for temperature change.\n";
            }
        }
	else {
            printf("  Temperature is unchanged. No focus adjustment necessary.\n");
	}

    # Now adjust the guider's focus point individually. This needs to be tweaked whenever the guider is
    # changed.
    $adjust_guider_separately = 1;
    $guider_lens = "83F010692";
    if ($adjust_guider_separately) {
        chomp($estimated_guider_focus = `predict_focus $guider_lens`);
        `birger_client $guider_lens goto $estimated_guider_focus`;  
        if ($?) {
            print "  Error changing focus\n";
        }
        else {
            print "  Focus changed\n";
        }
    }
    }

    # Get the data if the roof is open and the sky quality is reasonable. Skip and sleep if the roof is closed
    # or if the sky quality is lousy
    $roof = `nms_roof_status`;
    $skyqual = `nms_sky_conditions`;
    if (($roof !~ /Closed/ && $skyqual =~ /Clear|Patchy/) || $debug > 0) {

        # Try to guide - we retry a single time in the event of a failure.
        $currently_guiding = 0;
        if ($guide && (-e "DO_NOT_GUIDE.txt")) {
            print "  DO_NOT_GUIDE.txt file found. No guiding will be attempted.\n";
        }
        elsif ($guide) {
            print "  Attempting to autoguide\n" if $verbose;
            $start_time = DateTime->now();
            `syslog -s -l alert [DragonflyStatus] auto_observe - searching for guide star`;
            $guide_command = "guider magic";
            print "    Guider command issued: $guide_command\n" if ($verbose);
            `$guide_command`; 
            if ($?) {
                print "    Guider command failed. Trying one more time.\n";
                `$guide_command`;
            }
            if ($?){
                `syslog -s -l alert [DragonflyStatus] auto_observe - guider magic could not initiate guiding.`;
                print "    Guider could not find a suitable star. Not guiding.\n";
                $currently_guiding = 0;
            }
            else {
                # Success - we've found a guide star and are guiding on it
                `syslog -s -l alert [DragonflyStatus] auto_observe - guiding.`;
                print "    Success. Pausing for 5s so guide star can center itself in the track box.\n";
                $currently_guiding = 1;
                $n_guided++ ;
                sleep 5;
            }
            $guider_setup_time += report_timing($start_time,$verbose);
        }
        else {
            print "  Not autoguiding.\n" if ($verbose);
        }

        # Get science data
        $n_target++;
        $now = `date`;
        chop($now);
        printf("  Integrating for $exptime seconds.\n") if ($verbose);
        $nicetarget = $target;
        $nicetarget =~ s/\s/_/g;
        $frame_type = "light";
        $start_time = DateTime->now();
        `syslog -s -l alert [DragonflyStatus] auto_observe - taking science data.`;
        $new_frames = `all_expose --name $nicetarget $frame_type $exptime`;
        `syslog -s -l alert [DragonflyStatus] auto_observe - science integrations complete.`;
        $readout_time += report_timing($start_time,$verbose) - $exptime;
        $science_time += $exptime;

        # Once the data is in we set a task running on the data server to append metadata to the headers. This next part is
        # very fiddly so don't mess with it now that it is working!
        print "  Instructing the server to compute metadata in the background and store it in the headers.\n" if $verbose;
        $start_time = DateTime->now();
        my @lines = split("\n",$new_frames);
        my $files_to_analyze = "";
        foreach $line (@lines) {
            $line =~ /^(\[.+\]) (.+)(_.+)(_.+)/;
            $ip = $1;
            my $serial_number = $2;
            my $filename = $2 . $3 . $4;
            chomp(my $dirname = `camera_info -c $serial_number arraydir`);
            my $full_filename = "$dirname/$tonightdir/$filename";
            $full_filename =~ s/\s+//g;
            $files_to_analyze = "$files_to_analyze $full_filename";
        }
        $all_files_obtained = "$all_files_obtained $files_to_analyze";

        # Send a command to the server instructing it to start post-processing the new files.
        # This also generates an email to the user summarizing the status of the observations
        # determined using the Astromatic tools.
        $subject = sprintf("'post-processing results - auto_observe iteration %d.'",$iteration+1);
        $files_to_analyze = "-s $subject $files_to_analyze";
        `df_send dataserver "post_process $files_to_analyze"`;
        $store_metadata_time += report_timing($start_time,$verbose);

        # Stop guiding and email a graphical summary of the guiding log
        if ($currently_guiding) {
            print "  Stopping autoguider\n" if $verbose;
            $start_time = DateTime->now();
            $guide_command = "guider stop";
            print "    Guider command issued: $guide_command\n" if ($verbose);
            `$guide_command`; 
            $guider_setup_time += report_timing($start_time,$verbose);
            `syslog -s -l alert [DragonflyStatus] auto_observe - stopped guiding.`;
            $subject = sprintf("autoguider plots - auto_observe iteration %d.",$iteration+1);
            `email_guider_plots -s "$subject"`;
        }

        # See if the user wants to bail out early. If so, now is a good time to do it.
        &check_for_interrupt_file($currently_guiding);
        &check_for_next_target_file($currently_guiding);

        # Touch up the focus
        if ($tweak) {
            $start_time = DateTime->now();
            print "  Initiating a short focus run to touch up the focus.\n" if ($verbose);
            `all_focus --nomail --simple --force superfine`; 
            $focus_time += report_timing($start_time,$verbose);
        }

        # If there was an issue with the autoguider then disconnect and reconnect it. If we've already tried this
        # once before then augment with a power cycle. 
        if ($guide && !$currently_guiding) {
            print "  Disconnecting and reconnecting autoguider\n" if $verbose;
            $start_time = DateTime->now();
            $guide_command = "guider disconnect";
            print "    Guider command issued: $guide_command\n" if ($verbose);
            `$guide_command`; 
            `syslog -s -l alert [DragonflyStatus] auto_observe - disconnected autoguider.`;
            if ($tried_to_fix_guider) {
                `power guider off`;
                sleep 10;
                `power guider on`;
                sleep 10;
                `syslog -s -l alert [DragonflyStatus] auto_observe - power cycled autoguider camera.`;
            }
            $guide_command = "guider connect";
            print "    Guider command issued: $guide_command\n" if ($verbose);
            `$guide_command`; 
            `syslog -s -l alert [DragonflyStatus] auto_observe - reconnected autoguider.`;
            $guider_setup_time += report_timing($start_time,$verbose);
            $tried_to_fix_guider = 1;
        }

    }
    else {
        print "  Roof is closed or skies are cloudy or moon is up. Pausing for 1.3 * $exptime seconds\n" if ($verbose);
        `syslog -s -l alert [DragonflyStatus] auto_observe - cloudy or moonlight or roof closed. Pausing for 1.3 x $exptime seconds.`;
        if ($exptime > 3 && $verbose) {
            sleep(1);
            my $progress = Term::ProgressBar->new({
                    name => '  Progress',
                    count => int(1.3*$exptime)
                });
            $progress->max_update_rate(1);
            my $next_update = 0;

            for (0..int(1.3*$exptime)) {
                $next_update = $progress->update($_) if $_ > $next_update;
                sleep(1);
            }
            $progress->update($exptime) if $exptime >= $next_update;
        }
        print "Wall-clock exposure time expired. CCDs should be reading out now.\n" if $verbose;
    }
    sleep(1);

    last if ($debug && $iteration==2);

    die "Exiting due to manual interrupt.\n" if $exit_asap;
}

# Now is another logical time to bail out
&check_for_interrupt_file($currently_guiding);
&check_for_next_target_file($currently_guiding);

# Restoring position on target
print "  Returning to original target.\n" if $verbose;
$start_time = DateTime->now();
$slew_command = "mount --host $host goto $target";
print "    Slew command issued: $slew_command\n" if ($verbose);
`syslog -s -l alert [DragonflyStatus] auto_observe - slewing.`;
`$slew_command`;
`syslog -s -l alert [DragonflyStatus] auto_observe - slew complete.`;
$slew_time += report_timing($start_time,$verbose);

# Obtain a long dark at the end
if ($dark) {
    print "\nObtaining a dark frame.\n" if $verbose;
    `syslog -s -l alert [DragonflyStatus] auto_observe - taking dark frame.`;
     $start_time = DateTime->now();
    $new_frames = `all_expose dark $exptime`;
    $dark_time += report_timing($start_time,$verbose);

    # Once the data is in we set a task running on the data server to append metadata to the headers. This next part is
    # very fiddly so don't mess with it now that it is working!
    print "  Instructing the server to compute metadata in the background and store it in the headers.\n" if $verbose;
    $start_time = DateTime->now();
    my @lines = split("\n",$new_frames);
    my $files_to_analyze = "";
    foreach $line (@lines) {
        $line =~ /^(\[.+\]) (.+)(_.+)(_.+)/;
        $ip = $1;
        my $serial_number = $2;
        my $filename = $2 . $3 . $4;
        chomp(my $dirname = `camera_info -c $serial_number arraydir`);
        my $full_filename = "$dirname/$tonightdir/$filename";
        $full_filename =~ s/\s+//g;
        $files_to_analyze = "$files_to_analyze $full_filename";
    }
    $all_files_obtained = "$all_files_obtained $files_to_analyze";
}
else{
    print "  No dark frame will be taken (--nodark)\n" if $verbose;
}

# If nothing was observed we don't bother reporting anything...
if ($n_target == 0) {
    print "No targets observed. No email will be sent.\n";
    exit;
}

# Analyze overheads
$overhead_time = $slew_time + $dither_time + $focus_time + $dark_time + 
                 $guider_setup_time + $readout_time + 
                 $store_metadata_time;

open(OVERHEADS,">/var/tmp/overheads.txt");
printf(OVERHEADS "Summary\n");
printf(OVERHEADS "  Science target time (s)... %d\n",$science_time);
printf(OVERHEADS "  Overhead time (s)......... %d\n",$overhead_time);
printf(OVERHEADS "  Total time (s)............ %d\n",$science_time + $overhead_time);
printf(OVERHEADS "  Efficiency (%)............ %-4.1f\n",100.0*$science_time/($science_time + $overhead_time));
printf(OVERHEADS "\n");
printf(OVERHEADS "Breakdown of overheads\n");
printf(OVERHEADS "  Slewing (s)............... %d\n",$slew_time);
printf(OVERHEADS "  Dithering (s)............. %d\n",$dither_time);
printf(OVERHEADS "  Focusing (s).............. %d\n",$focus_time);
printf(OVERHEADS "  Darks (s)................. %d\n",$dark_time);
printf(OVERHEADS "  Guider setup (s).......... %d\n",$guider_setup_time);
printf(OVERHEADS "  Readout (s)............... %d\n",$readout_time);
printf(OVERHEADS "  Metadata (s).............. %d\n",$store_metadata_time);
printf(OVERHEADS "\n");
close(OVERHEADS);
open (OVERHEADS, "</var/tmp/overheads.txt");
@file_contents = <OVERHEADS>;
close(OVERHEADS);
print "\n";
foreach (@file_contents){ print $_;}

# Upload a JPG image to the server showing the all-sky camera view of the end of the sequence
print "Uploading all-sky image to the data server\n";
`upload_all_sky_image end_sky.jpg`;

# Upload a GIF image to the server showing the weather
print "Uploading weather chart to the data server\n";
`upload_weather weather.gif`;

# Upload a PNG image to the server showing the desktop
print "Uploading desktop screenshot to the data server\n";
`upload_screenshot capture.png`;

# Instruct the data server to email a summary of the observations to the user. We need to be
# quite careful to get the quoting right so don't mess with the next few lines.
print "Instructing the server to email a report to the user\n" if $verbose;
$target =~ s/\'//g;
$subject = "'auto_observe summary - target:$target, guided:$n_guided/$n_target'";
$all_files_obtained = "-s $subject $all_files_obtained";
`df_send dataserver "report $all_files_obtained"`;

# We made it to the end!
`syslog -s -l alert [DragonflyStatus] auto_observe completed. Result: $n_target pointings, $n_guided guided.`;
$end = `date`;
print "Auto_observe finished at $end" if $verbose;



############

sub check_for_interrupt_file {
     my($is_guiding)=@_;
     if (-e "INTERRUPT.txt") {
        if ($is_guiding){
            print "Stopping autoguider corrections.\n" if ($verbose);
            `guider stop` ;
        }
        `syslog -s -l alert [DragonflyStatus] auto_observe aborted - INTERRUPT.txt file found.`;
        die "Exiting early because the INTERRUPT.txt file has been found";
    }
}

sub check_for_next_target_file {
     my($is_guiding)=@_;
     if (-e "NEXT_TARGET.txt") {
        if ($is_guiding){
            print "Stopping autoguider corrections.\n" if ($verbose);
            `guider stop` ;
        }
        `syslog -s -l alert [DragonflyStatus] auto_observe aborted - NEXT_TARGET.txt file found.`;
        `rm -f NEXT_TARGET.txt`;
        die "Exiting early because the NEXT_TARGET.txt file has been found";
    }
}

sub interrupt {
     my($signal)=@_;
     print "Caught Interrupt\: $signal \n";
     print "The program will exit cleanly after the next integration is completed.\n";
     $exit_asap = 1;
}


sub report_timing {
    my $start_time = shift;
    my $verbose = shift;
    my $end_time = DateTime->now();
    my $elapsed_time = ($end_time->subtract_datetime_absolute($start_time))->in_units('seconds');
    print "  Done (took $elapsed_time seconds).\n" if ($verbose);
    return($elapsed_time);
}


__END__

=head1 NAME

auto_observe - Obtain CCD data on a target object

=head1 SYNOPSIS

auto_observe [options] target

options:
 
 --exptime seconds        (default 600)
 --dither_angle arcmin    (default 10)
 --[no]focus              (default --focus)
 --[no]tweakfocus         (default --notweak)
 --[no]guide              (default --guide)
 --[no]dark               (default --dark)
 --[no]debug              (default --debug)
 --help
 --man

=head1 ARGUMENTS

=over 8

=item B<target>

The name of the target in TheSkyX's database. This is usually given as a prefix
then a space then a number, all enclosed by quotes.  For example "M 33" or "DF
51" or "NGC 4151".

=back

=head1 OPTIONS

=over 8

=item B<--exptime time>

Integration time in seconds (default is --exptime 600).

=item B<--dangle arcmin>

Dither angle in arcminutes (default is 10).

=item B<--[no]focus>

Do a focus run at the start of the observation sequence (default is --focus).

=item B<--[no]guide>

Attempt to autoguide at each dither position (default is --guide).

=item B<--[no]tweakfocus>

Refocus halfway through the observation sequence (default is --tweakfocus).

=item B<--[no]dark>

Take a dark frame at the end of the integrations (default is --dark).

=item B<--[no]debug>

Run in a debug mode. If --debug is set then the system will attempt to gather data even
if the roof is closed (which facilitates testing during daytime) and the sequence will
bail out after the third iteration rather than execute the whole sequence.

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<auto_observe> slews to an object then collects data using a 9-point square
dither pattern.

The dither sequence starts at the central object position and then goes round
the sky in a counterclockwise direction in 45 deg increments. So it looks like
this:

                      5   4   3 
                      6   1   2 
                      7   8   9

By default at the start of the sequence a focus run is performed and another
focus run is done when the sequence hits dither position 5. This behaviour can
be adjusted with the --[no]focus and --[no]tweakfocus options.

By default the script attempts to guide at each dither position. This can be
changed with the --[no]guide option.

By default after the sequence is complated a dark frame is taken. This can be
changed using the --[no]dark option. 

With 600s integrations this script takes about two hours to run (including
overheads for focusing and readout).

=head1 EXAMPLES

=over 4

Generic observation:

 % auto_observe "NGC 1275"

To play with this script during the daytime with 5s integrations:

 % auto_observe --debug --noguide --nofocus --notweak -exptime 5 "M 13"

To continuously monitor the progress of auto_observe run the following command in its own window:

syslog -w -k Message Req TheSkyX -k Time ge -12h -o -k Message Req Dragonfly -k Time ge -12h | grep -v 'Authentication: SUCCEEDED'

=cut
