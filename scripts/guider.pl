#!/usr/bin/perl

use Getopt::Long qw(:config require_order); 
use DateTime;
use Pod::Usage;
use Time::HiRes;

# IMPORTANT! Do not buffer output!
$|=1;

# Specify the locations of some important files
$logfile = "/Users/dragonfly/Library/Application Support/Software Bisque/TheSkyX Professional Edition/LogIS2.txt";
$original_logfile = "/var/tmp/guider_original.txt";

# Parse command-line options
my $verbose = 0;
my $exptime = 10;
my $host = "localhost";
my $port = "XXXX";
my $maestro = 1; 
my $safe = 0;
my $help = 0;
my $man = 0;
my $bin = 1;

$result = GetOptions(
    "verbose!" => \$verbose,
    "maestro!" => \$maestro,
    "safe!" => \$safe,
    "keyboard!" => \$maestro,
    "bin=i" => \$bin,
    "exptime=f" => \$exptime,
    "host=s" => \$host,
    "help|?" => \$help, 
     man=> \$man) or pod2usage(2);
pod2usage(0) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

# Copy the log to a temporary file
`cp "$logfile" "$original_logfile"`;

$command = lc(shift);

# If the DO_NOT_GUIDE.txt file exists bail out
if (-e "DO_NOT_GUIDE.txt") {
    die "DO_NOT_GUIDE.txt file found. No guiding will be attempted.\n";
}

# Figure out how to send commands
if ($maestro) {
    $maestro_flag = "--maestro";
}
else {
    $maestro_flag = "--nomaestro";
}


# Define the Javascript
if ($command =~ /reset/) {
    
    $javascript = <<END;
    /* Java Script */

    var Out="";
    ccdsoftCamera.Autoguider = 1;
    ccdsoftCamera.Asynchronous = false;
    ccdsoftCamera.Disconnect();
    ccdsoftCamera.Connect();
    Out = "Camera connection reset";
END
}

elsif ($command =~ /set/) {
    
    my $x = shift;
    my $y = shift;

    $javascript = <<END;
    /* Java Script */

    var Out="";
    var x,y;
    ccdsoftCamera.Autoguider = 1;
    ccdsoftCamera.Asynchronous = true;
    if (ccdsoftCamera.Connect()) {
       Out = "DFError: Not connected";
    } else {
       ccdsoftCamera.BinX = $bin;
       ccdsoftCamera.BinY = $bin;
       ccdsoftCamera.GuideStarX = $x;
       ccdsoftCamera.GuideStarY = $y;
       ccdsoftCamera.MoveToX = $x;
       ccdsoftCamera.MoveToY = $y;
      Out = "Guiding at x=$x y=$y.";
    }
END
}

elsif ($command =~ /start/) {
    
    $javascript = <<END;
    /* Java Script */

    var Out="";
    ccdsoftCamera.Autoguider = 1;
    if (ccdsoftCamera.Connect()) {
       Out = "DFError: Not connected";
    } else {
       ccdsoftCamera.AutoSaveOn = false;
       ccdsoftCamera.AutoguiderExposureTime = $exptime;
       ccdsoftCamera.AutoguiderDelayAfterCorrection = 1;
       ccdsoftCamera.Asynchronous = true;
       ccdsoftCamera.BinX = $bin;
       ccdsoftCamera.BinY = $bin;
        ccdsoftCamera.TrackBoxX = 35;
       ccdsoftCamera.TrackBoxY = 35;
       ccdsoftCamera.Autoguide(); 
       Out = "Guiding started";
    }
END
}

elsif ($command =~ /^disconnect/i) {
    
    $javascript = <<END;
    /* Java Script */

    var Out="";
    ccdsoftCamera.Autoguider = 1;
    ccdsoftCamera.Disconnect();
    Out = "Camera disconnected";
END
}

elsif ($command =~ /^connect/i) {
    
    $javascript = <<END;
    /* Java Script */

    var Out="";
    var count = 0;
    ccdsoftCamera.Autoguider = 1;
    ccdsoftCamera.Connect();
    Out = "Camera connected";
END
}

elsif ($command =~ /^regulate/i) {
    
    $javascript = <<END;
    /* Java Script */

    var Out="";
    var count = 0;
    ccdsoftCamera.Autoguider = 1;
    ccdsoftCamera.Connect();
    ccdsoftCamera.TemperatureSetPoint = -5;
    ccdsoftCamera.RegulateTemperature = 1;
    ccdsoftCamera.ShutDownTemperatureRegulationOnDisconnect = 0;
    Out = "Camera connected";
END
}

elsif ($command =~ /stop/) {
    
    $javascript = <<END;
    /* Java Script */

    var Out="";
    ccdsoftCamera.Autoguider = 1;
    ccdsoftCamera.Asynchronous = true;
    if (ccdsoftCamera.Connect()) {
       Out = "DFError: Not connected";
    } else {
        ccdsoftCamera.Abort();
        state = ccdsoftCamera.State;
        while (ccdsoftCamera.State != 0) {
          sky6Web.Sleep(1000);
        }
        Out = "Guiding stopped.";
    }
END
}

elsif ($command =~ /^image/) {
    
    $javascript = <<END;
    /* Java Script */

    var Out="";
    var path = ""
    var filename = "";
    var keep = ccdsoftCamera.AutoSaveOn;
    var im;

    ccdsoftCamera.Autoguider = 1;
    ccdsoftCamera.BinX = $bin;
    ccdsoftCamera.BinY = $bin;
    ccdsoftCamera.AutoguiderExposureTime = $exptime;
    ccdsoftCamera.Asynchronous = false;
    if (ccdsoftCamera.Connect()) {
       Out = "DFError: Not connected";
    } else {
        ccdsoftCamera.Abort();
        while (ccdsoftCamera.State != 0) {
          sky6Web.Sleep(1000);
        }
        ccdsoftCamera.AutoSaveOn = false;
        ccdsoftCamera.ImageReduction = 0;
        ccdsoftCamera.TakeImage();
        while (ccdsoftCamera.State != 0) {
          sky6Web.Sleep(1000);
        }
        im = ccdsoftAutoguiderImage;
        im.AttachToActiveAutoguider();
        im.Path = "/var/tmp/guider_image.fits";
        im.setFITSKeyword("GUIDER","success");
        im.Save();

        ccdsoftCamera.AutoSaveOn = keep;
        Out = "Test image stored in /var/tmp/guider_image.fits";
    }
END
}

elsif ($command =~ /list|magic/) {
    $javascript = "";
}

else {
    print "Error: command not found\n";
    exit(1);
}

# If we're in safe mode then override the communication mode if the socket is blocked
if ($safe) {
    `check_socket`;
    if ($?){
        my $error_message = "[DragonflyError] guider error: socket blocked. Forcing use of KeyboardMaestro.";
        `syslog -s -l alert $error_message`;
        $maestro = 1;
    }
}

# Deliver the JavaScript
if ($javascript) {
    &send_javascript($javascript,$maestro);
#    $err = &wait_for_unchanging("$logfile","ccdsoftCamera::TakeImage Exit.",30) if $command =~ /^image/i;
#    $err = &wait_for_unchanging("$logfile","ccdsoftCamera::Connect Exit.",30) if $command =~ /^connect|^reset|^set/i;
#    $err = &wait_for_unchanging("$logfile","ccdsoftCamera::Disconnect Exit.",30) if $command =~ /^disconnect/i;
#    $err = &wait_for_unchanging("$logfile","ccdsoftCamera::Autoguide Exit.",30) if $command =~ /^start/i;
#    $err = &wait_for_unchanging("$logfile","ccdsoftCamera::Abort Exit.",30) if $command =~ /^stop/i;

    $err = &wait_for("$logfile","$original_logfile","ccdsoftCamera::TakeImage Exit.",30) if $command =~ /^image/i;
    $err = &wait_for("$logfile","$original_logfile","ccdsoftCamera::Connect Exit.",30) if $command =~ /^connect|^reset|^set/i;
    $err = &wait_for("$logfile","$original_logfile","ccdsoftCamera::Disconnect Exit.",30) if $command =~ /^disconnect/i;
    $err = &wait_for("$logfile","$original_logfile","ccdsoftCamera::Autoguide Exit.",30) if $command =~ /^start/i;
    $err = &wait_for("$logfile","$original_logfile","ccdsoftCamera::Abort Exit.",30) if $command =~ /^stop/i;

    # Some tweaks that might prove helpful
    sleep(3) if $command =~ /^connect/i;
}
else {

    if ($command =~ /list/) {

        # This is a good filter when using a Canon EF400 lens as an autoguider (un-binned):
        $cmd1 = "extract /var/tmp/guider_image.fits | ";
        $cmd2 = "tfilter 'FLAGS==0 && FLUX_ISO>10000 && ISOAREA_IMAGE<200 && FLUX_MAX<30000 && X_IMAGE>50 && X_IMAGE<2000 && Y_IMAGE>50 && Y_IMAGE<2000' | ";
        $cmd3 = "tcolumn X_IMAGE Y_IMAGE FLUX_ISO | sort -r -n -k 3 | awk '{print \$1-0.5,\$2-0.5}'";

        # This is a good filter when using an ST-i or ST-402:
        # $cmd1 = "extract /var/tmp/guider_image.fits | ";
        # $cmd2 = "tfilter 'FLAGS==0 && FLUX_ISO>3000 && ISOAREA_IMAGE<200 && FLUX_MAX<50000 && ";
        # $cmd3 = "X_IMAGE>30 && X_IMAGE<600 && Y_IMAGE>30 && Y_IMAGE<480' | ";
        # $cmd4 = "tcolumn X_IMAGE Y_IMAGE FLUX_ISO | sort -r -n -k 3 | awk '{print \$1-0.5,\$2-0.5}'";

        $cmd_all = "$cmd1 $cmd2 $cmd3 $cmd4";
        $result = `$cmd_all`;
        die 'Could not list stars' if $?;
        print $result;
    }

    if ($command =~ /magic/) {

        `rm -f /var/tmp/guider_image.fits`;

        # This is meant to deal with timeouts in a sneaky way
        `guider $maestro_flag disconnect`;
        # `expose light 1`;

        print "Starting exposure\n";
        my $result = `guider $maestro_flag --exptime $exptime --bin $bin --host $host image`;
        die 'Error taking image' if $?;

        print "Waiting for image to be saved to disk.\n";
        my $count = 0;
        my $timeout = 30;
        while(! -e "/var/tmp/guider_image.fits") {
            sleep(1);
            $count++;
            die "Guider image failed to appear" if ($count>$timeout);
        }
        sleep(1);

        print "Finding stars\n";
        `guider $maestro_flag  --bin $bin --host $host list > /var/tmp/stars.txt`;
        die 'Could not list guide stars' if $?;
        # Do a sanity check... if there are very few stars then it's cloudy and we don't want to guide
        $nstars = `wc /var/tmp/stars.txt | awk '{print \$1}'`;
        chop($nstars);
        print "Nstars=$nstars\n";

        print "Selecting the best star and guiding on it.\n"; 
        sleep 2;
        if ($nstars >= 2) {
            # The next line will need to be modified if I ever start to use binning
            $star = `head -1 /var/tmp/stars.txt | awk '{print \$1,\$2}'`;
            chop($star);
            print "Setting guider to track star at $star (in native TheSkyX coordinates)\n"; 
            `guider $maestro_flag --bin $bin --host $host set $star`;
            die 'Could not set guide star' if ($?);
            sleep 2;
            print "Start autoguiding...\n";
            `guider $maestro_flag --bin $bin --host $host start`;
            die 'Could not start guiding' if ($?);
        }
        else {
            die "Error: Too few guide stars found. Not autoguiding\n";
        }
    }
}



#########

sub wait_for {
    my $current_logfile = shift;
    my $original_logfile = shift;
    my $magic = shift;
    my $timeout = shift;
    my $line = "";
    my $current = 0;
    my $wait_interval = 0.2;
    while ($line !~ /$magic/ && $current < $timeout) {
        chomp($line = `diff "$current_logfile" "$original_logfile" | tail -1`);

        # check if the line is reporting an error.
        if ($line =~ /.*error = (\d+)/) {
            $errnum = $1;
            die "error $errnum" if $errnum > 0;
        }
        $current += $wait_interval;
        Time::HiRes::sleep($wait_interval);
    }
    die "mount.pl timed out" if ($current == $timeout);
    $line =~ /.*error = (\d+)/;
    return $1;
}

#########

sub wait_for_unchanging {
    my $current_logfile = shift;
    my $magic = shift;
    my $timeout = shift;

    my $line = "";
    my $newline = "";
    my $current = 0;
    my $wait_interval = 2;
    my $line_changed = 1;

    sleep 1;
    while ($line_changed && $current < $timeout) {
        chomp($line = `tail -1 "$current_logfile"`);

        print "--> $line\n";

        # Check if the line is reporting an error.
        if ($line =~ /.*Error = (\d+)/) {
            $errnum = $1;
            die "-> Error $errnum" if $errnum > 0;
        }

        $current += $wait_interval;
        sleep $wait_interval;

        # Check if line has changed in the last wait interval
        chomp($newline = `tail -1 "$current_logfile"`);
        $line_changed = 0 if ($newline eq $line);

    }
    die "Guider.pl timed out" if ($current == $timeout);
    $newline =~ /.*Error = (\d+)/;
    $errnum = $1;
    die "Error $errnum" if $errnum > 0 || $newline !~ /$magic/ ;
    return $errnum;
}


#########

sub send_javascript {

    my $javascript = shift;
    my $method = shift;

    open(COMMANDFILE,">/var/tmp/tmp.js");
    print COMMANDFILE $javascript;
    close(COMMANDFILE);
    if (!$maestro) {
        # Send the command via TCP
        print "Sending JavaScript by connecting to a socket on TheSkyX's TCP Server.\n" if $verbose;
        `skysend localhost /var/tmp/tmp.js`;
        if ($?) {
            $error_message = "[DragonflyError] mount error reported after sending JavaScript";
            `syslog -s -l alert $error_message`;
            die 'mount command failed when sending JavaScript';
        }
    }
    else {
        # Send the command via the Keyboard Maestro Engine
        print "Sending JavaScript via the Keyboard Maestro Engine.\n" if $verbose;
        system( 'osascript', '-e', <<EOM );
tell application "Keyboard Maestro Engine"
do script "Send JavaScript to TheSkyX"
end tell
EOM
        die "Communication error via KeyboardMaestro" if $?;
    }
}


__END__

=head1 NAME

guider - control autoguider

=head1 SYNOPSIS

guider command [arguments]

=head1 ARGUMENTS

=over 8

=item B<command>

One of "magic", "image", "list", "train", "set," "bin", "start", or "stop". 

 magic      - attempt to start autoguiding with minimal setup, as if by magic
 image      - take an image and store it in /var/tmp/guider_image.fits
 list       - find suitable guider stars on the most recent autoguider image
 set x y    - use a guide star at pixel x,y on the autoguider chip
 start      - initiate autoguiding
 stop       - stop autoguiding

=back

=head1 OPTIONS

=over 8

=item B<--host IP>

IP address of the machine with the TheSkyX JavaScript command server. The default is XXX.XXX.XXX.XXX

=item B<--k>

Send commands using Keyboard Maestro rather than over a TCP/IP socket.

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<guider> attempts to control the autoguider.

=head1 EXAMPLES 

 % guider magic
 % guider image
 % guider list
 % guider select 803 339
 % guider start 
 % guider stop

=cut

