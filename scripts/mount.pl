#!/usr/bin/perl

use Getopt::Long qw(:config require_order); 
use Pod::Usage;
use Time::HiRes;

# DEBUG ME WITH:
#
# sudo tcpdump -i lo0 port 3040
# sudo tcpdump -i lo0 -vv port 3040
# sudo tcpdump -i lo0 -A 'port 3040 && tcp[tcpflags] & (tcp-syn | tcp-fin) != 0'

# IMPORTANT! Do not buffer output!
$|=1;

# Specifiy the locations of some important files
$position_file = "/Users/dragonfly/Documents/Telescope\ Position.txt";
$logfile = "/Users/dragonfly/Library/Application Support/Software Bisque/TheSkyX Professional Edition/LogIS1.txt";
$original_logfile = "/var/tmp/mount_original.txt";

# Parse command-line options
my $comment = "";
my $man = 0;
my $host = "localhost";
my $port = 3040;
my $maestro = 1;   # Alternative to TCP/IP
my $safe = 0;      # If socket is blocked use backup method 
my $async = 0;
my $location = "NewMexicoSkies";
my $help = 0;
my $verbose = 0;

$result = GetOptions(
    "verbose!" => \$verbose,
    "async!" => \$async,
    "maestro!" => \$maestro,
    "keyboard!" => \$maestro,
    "safe!" => \$safe,
    "comment=s" => \$comment,
    "location=s" => \$location,
    "host=s" => \$host,
    "help|?" => \$help, 
     man=> \$man) or pod2usage(2);
pod2usage(0) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

# Copy the log to a temporary file
`touch $logfile` if !(-e $logfile); 
`cp "$logfile" "$original_logfile"`;

$command = lc(shift);

if ($command =~ /^position/i) {
    $javascript = <<END;
    /* Java Script */

    var Out;
    var dRA;
    var dDec;
    var dAz;
    var dAlt;
    var coordsString1;
    var coordsString2;

    sky6RASCOMTele.Connect();
    if (sky6RASCOMTele.IsConnected==0) {
        Out = "Not connected"
    } else {
        sky6RASCOMTele.GetRaDec();
        dRA = sky6RASCOMTele.dRa;
        dDec = sky6RASCOMTele.dDec;
        sky6Utils.ComputeHourAngle(dRA);
        dHA = sky6Utils.dOut0;
        sky6Utils.ConvertEquatorialToString(dRA,dDec,5);
        coordsString1 = sky6Utils.strOut;
        sky6RASCOMTele.GetAzAlt();
        Out = coordsString1;
        Out += " Alt: " + parseFloat(Math.round(sky6RASCOMTele.dAlt*100)/100).toFixed(2); 
        Out += " Az: " + parseFloat(Math.round(sky6RASCOMTele.dAz*100)/100).toFixed(2); 
        Out += " HA: " + parseFloat(Math.round(dHA*10000)/10000).toFixed(4); 
    };
END
}

elsif ($command =~ /^sync/i) {
    $javascript = <<END;
    /* Java Script */

    var im = ccdsoftCameraImage;
    var tmpfile = "/var/tmp/tmp.fits";
    ImageLink.scale = 2.85;
    ccdsoftCamera.CameraExposureTime = 5;

    // Take the image
    ccdsoftCamera.Autoguider = true;
    ccdsoftCamera.Asynchronous = false;
    if (ccdsoftCamera.Connect()) {
      Out = "Not connected";
      return;
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
      im.Path = tmpfile;
      im.Save();
      ccdsoftCamera.AutoSaveOn = true;
    }

    // ImageLink the image and sync the telescope to it
    ImageLink.pathToFITS = tmpfile;
    ImageLink.unknownScale = 0;
    try {
       ImageLink.execute();
    }
    catch(e) {   
      im.New(10,10,16);
      im.Visible = 0;
      im.DetatchOnClose = 1;
      im.Path = "/var/tmp/mount_sync_output.fits"; 
      im.setFITSKeyword("RESULT","failed");
      im.Save();
      im.Close();
    }

    im.New(10,10,16);
    im.Visible = 0;
    im.DetatchOnClose = 1;
    im.Path = "/var/tmp/mount_sync_output.fits"; 
    if (ImageLinkResults.succeeded) {
      im.setFITSKeyword("RESULT","success");
      im.setFITSKeyword("RA_PS",ImageLinkResults.imageCenterRAJ2000);
      im.setFITSKeyword("DEC_PS",ImageLinkResults.imageCenterDecJ2000);
      im.setFITSKeyword("SCALE_PS",ImageLinkResults.imageScale);
      im.setFITSKeyword("ISMIR_PS",ImageLinkResults.imageIsMirrored);
      sky6RASCOMTele.Connect();
      sky6RASCOMTele.Sync(ImageLinkResults.imageCenterRAJ2000, ImageLinkResults.imageCenterDecJ2000, "plate_solve"); 
      Out = "Telescope synced to image";
    }
    else {
      im.setFITSKeyword("RESULT","failure");
      Out = "ImageLink failed. Telescope is not synced.";
    }
    im.Save();
    im.Close();
  
END
}



elsif ($command =~ /^goto/i) {
    $target = shift;
    $javascript = <<END;
    /* Java Script */

    var Target = "$target";
    var TargetRA=0;
    var TargetDec=0;
    var Out="";
    var err;
    sky6StarChart.LASTCOMERROR=0;
    sky6StarChart.Find(Target);
    err = sky6StarChart.LASTCOMERROR;
    if (err != 0)
    {
    	Out =Target + " not found.";
    }   
    else
    {
        sky6ObjectInformation.Property(54); /*RA_NOW*/
        TargetRA = sky6ObjectInformation.ObjInfoPropOut;

	    sky6ObjectInformation.Property(55); /*DEC_NOW*/
        TargetDec = sky6ObjectInformation.ObjInfoPropOut;
        Out = String(TargetRA) + "|"+ String(TargetDec);

        sky6RASCOMTele.Connect();
        if (sky6RASCOMTele.IsConnected==0) {
            Out = "Not connected";
        } else {
            sky6RASCOMTele.Asynchronous = $async;
            sky6RASCOMTele.Abort();
            sky6RASCOMTele.SlewToRaDec(TargetRA, TargetDec,"");
            while(!sky6RASCOMTele.IsSlewComplete) {
                sky6Web.Sleep(1000);
            }
            Out = "Slew complete.";
        }
    }
END
}

elsif ($command =~ /^dither/i) {
    $arcmin = shift;
    $direction = shift;
    $direction =~ tr/a-z/A-Z/; # So "N", "n", "North", "north", "NoRtH" all work
    die "Unknown direction" if ($direction !~ /^N|^S|^E|^W|^U|^D|^L|^R/);
    $direction = "'" . $direction . "'";

    $javascript = <<END;
    /* Java Script */

    var Out="";
    sky6RASCOMTele.Connect();
    if (sky6RASCOMTele.IsConnected==0) {
       Out = "Not connected";
    } else {
        sky6RASCOMTele.Asynchronous = $async;
        sky6RASCOMTele.Abort();
        sky6RASCOMTele.Jog($arcmin,$direction);
        while(!sky6RASCOMTele.IsSlewComplete) {
            sky6Web.Sleep(1000);
        }
        Out = "Dither complete.";
    }
END
}


elsif ($command =~ /^radec/i) {
    my $ra = shift;
    my $dec = shift;
    
    $javascript = <<END;
    /* Java Script */

    var Out="";
    var dRA = 0.0;
    var dDec = 0.0;
    sky6RASCOMTele.Connect();
    if (sky6RASCOMTele.IsConnected==0) {
       Out = "Not connected";
    } else {
        sky6Utils.ConvertStringToRA(\"$ra\");
        dRA = sky6Utils.dOut0;
        Out = dRA;
        sky6Utils.ConvertStringToDec(\"$dec\");
        dDec = sky6Utils.dOut0;
        Out += " " + dDec;
        sky6RASCOMTele.Asynchronous = $async;
        sky6RASCOMTele.Abort();
        sky6RASCOMTele.SlewToRaDec(dRA,dDec,'radec_coords');
        while(!sky6RASCOMTele.IsSlewComplete) {
            sky6Web.Sleep(1000);
        }
        Out = "Slew to RA/Dec complete.";
    }
END
}

elsif ($command =~ /^decimal/i) {
    my $ra = shift;
    my $dec = shift;
    
    $javascript = <<END;
    /* Java Script */

    var Out="";
    var dRA = 0.0;
    var dDec = 0.0;
    sky6RASCOMTele.Connect();
    if (sky6RASCOMTele.IsConnected==0) {
       Out = "Not connected";
    } else {
        dRA = $ra;
        Out = dRA;
        dDec = $dec;
        Out += " " + dDec;
        sky6RASCOMTele.Asynchronous = $async;
        sky6RASCOMTele.Abort();
        sky6RASCOMTele.SlewToRaDec(dRA,dDec,'radec_coords');
        while(!sky6RASCOMTele.IsSlewComplete) {
            sky6Web.Sleep(1000);
        }
        Out = "Slew to RA/Dec complete.";
    }
END
}

elsif ($command =~ /^altaz/i) {
    my $alt = shift;
    my $az = shift;
    
    $javascript = <<END;
    /* Java Script */

    var Out="";
    sky6RASCOMTele.Connect();
    if (sky6RASCOMTele.IsConnected==0) {
       Out = "Not connected";
    } else {
        sky6RASCOMTele.Asynchronous = $async;
        sky6RASCOMTele.Abort();
        sky6RASCOMTele.SlewToAzAlt($az,$alt,'altaz_coords');
        while(!sky6RASCOMTele.IsSlewComplete) {
            sky6Web.Sleep(1000);
        }
        Out = "Slew to Alt-Az complete.";
    }
END
}

elsif ($command =~ /^park/i) {
    $javascript = <<END;
    /* Java Script */

    var Out;
    sky6RASCOMTele.Connect();
    if (sky6RASCOMTele.IsConnected==0) {
        Out = "Not connected";
    } else {
        sky6RASCOMTele.Asynchronous = $async;
        sky6RASCOMTele.Abort();
        sky6RASCOMTele.Park();
        while(!sky6RASCOMTele.IsSlewComplete) {
            sky6Web.Sleep(1000);
        }
        Out = "Mount parked. LastSlewError: "+sky6RASCOMTele.LastSlewError;
    };
END
}

elsif ($command =~ /^home/i) {
    $javascript = <<END;
    /* Java Script */

    var Out;
    var Err;
    sky6RASCOMTele.Connect();
    if (sky6RASCOMTele.IsConnected==0) {
        Out = "Not connected";
    } else {
        sky6RASCOMTele.Abort();
        sky6RASCOMTele.FindHome();
        while(!sky6RASCOMTele.IsSlewComplete) {
            sky6Web.Sleep(1000);
        }
        Out = "Mount homed. LastSlewError: "+sky6RASCOMTele.LastSlewError;
     };
END
}

elsif ($command =~ /^start/i) {
    $javascript = <<END;
    /* Java Script */

    var Out;
    sky6RASCOMTele.Connect();
    if (sky6RASCOMTele.IsConnected==0) {
        Out = "Not connected";
    } else {
        sky6RASCOMTele.Abort();
        sky6RASCOMTele.SetTracking(1,1,0,0);
        Out = "Mount tracking at sidereal rate. LastSlewError: "+sky6RASCOMTele.LastSlewError;
     };
END
}

elsif ($command =~ /^stop/i) {
    $javascript = <<END;
    /* Java Script */

    var Out;
    sky6RASCOMTele.Connect();
    if (sky6RASCOMTele.IsConnected==0) {
        Out = "Not connected";
    } else {
        sky6RASCOMTele.Abort();
        sky6RASCOMTele.SetTracking(0,1,0,0);
        Out = "Mount tracking off. LastSlewError: "+sky6RASCOMTele.LastSlewError;
     };
END
}

elsif ($command =~ /^purge/i) {
    $javascript = <<END;
    /* Java Script */

    sky6RASCOMTele.Connect();
    if (sky6RASCOMTele.IsConnected==0) {
        Out = "Not connected"
    } else {
        sky6RASCOMTele.Abort();
        sky6RASCOMTele.DoCommand(0,"dummy");
        sky6RASCOMTele.DoCommand(1,"dummy");
        sky6RASCOMTele.DoCommand(2,"dummy");
        sky6RASCOMTele.DoCommand(6,"dummy");
        Out = "Serial port purged"; 
    };
END
}

elsif ($command =~ /^otaside/i) {
    $javascript = <<END;
    /* Java Script */

    var side;
    sky6RASCOMTele.Connect();
    if (sky6RASCOMTele.IsConnected==0) {
        Out = "Not connected"
    } else {
        sky6RASCOMTele.Abort();
        sky6RASCOMTele.DoCommand(11,"dummy");
        side = sky6RASCOMTele.DoCommandOutput;
        if (side == 0) {
          Out = "OTASide: West "; 
        }
        else {
          Out = "OTASide: East ";
        }
    };
END
}

else {
    die "Error: command not found\n";
}

# Make sure TheSkyX is running
print "Checking if TheSkyX is running.\n" if $verbose;
&check_theskyx();

# If we are running in 'safe' mode then override the communication mode if the socket is blocked
if ($safe) {
    `check_socket`;
    if ($?){
        my $error_message = "[DragonflyError] mount error: socket blocked. Forcing use of KeyboardMaestro.";
        `syslog -s -l alert $error_message`;
        $maestro = 1;
    }
}

# Special case: mount position is obtained from a file
if ($command =~ /position/i) {
    $result = `cat "$position_file"`;
    ($rahh,$ramm,$rass,$decdeg,$decmm,$decss,$azdeg,$azmm,$azss,$altdeg,$altmm,$altss) = split(/\s+|\|/,$result);
    
    $rahh =~ s/RA=//g;
    $rahh =~ s/h//g;
    $ramm =~ s/m//g;
    $rass =~ s/s//g;
    
    $decdeg =~ s/DEC=//g;
    $decdeg =~ s/°//g;
    $decmm =~ s/\'//g;
    $decss =~ s/\"//g;

    $altdeg =~ s/ALT=//g;
    $altdeg =~ s/°//g;
    $altmm =~ s/\'//g;
    $altss =~ s/\"//g;
    if ($altdeg !~ /\-/) {
        $alt = sprintf("%5.2f",$altdeg + $altmm/60 + $altss/3600);
    }
    else {
        $alt = sprintf("%5.2f",$altdeg - $altmm/60 - $altss/3600);
    }

    $azdeg =~ s/AZ=//g;
    $azdeg =~ s/°//g;
    $azmm =~ s/\'//g;
    $azss =~ s/\"//g;
    $az = sprintf("%6.2f",$azdeg + $azmm/60 + $azss/3600);

    print "$rahh:$ramm:$rass $decdeg*$decmm:$decss $alt $az UNKNOWN UNKNOWN\n";
    exit;
}

&send_javascript($javascript,$maestro);
$err = &wait_for("$logfile","$original_logfile","sky6RASCOMTele::SlewToRaDec Exit.",180) if $command =~ /goto|radec/i;
$err = &wait_for("$logfile","$original_logfile","sky6RASCOMTele::Jog Exit.",180) if $command =~ /dither/i;
$err = &wait_for("$logfile","$original_logfile","sky6RASCOMTele::SlewToAzAlt Exit.",180) if $command =~ /altaz/i;
$err = &wait_for("$logfile","$original_logfile","sky6RASCOMTele::FindHome Exit.",180) if $command =~ /home/i;
$err = &wait_for("$logfile","$original_logfile","sky6RASCOMTele::Park Exit.",180) if $command =~ /park/i;
$err = &wait_for("$logfile","$original_logfile","sky6RASCOMTele::DoCommand Exit.",20) if $command =~ /purge|otaside/i;
$err = &wait_for("$logfile","$original_logfile","sky6RASCOMTele::SetTracking Exit.",20) if $command =~ /start|stop/i;
if ($command =~ /sync/) {
    $timeout = 120;
    $count = 0;
    while(! -e "/var/tmp/mount_sync_output.fits" && $count<$timeout) {
       sleep(1);
       $count++;
    }
    chomp($result = `modhead /var/tmp/mount_sync_output.fits RESULT`);
    if ($result =~ /success/i) {
      print "Added WCS to $filename\n";
      exit(0);
    }
    else {
       die "ImageLink failed. Mount was not synced.\n";
    }
}


die "Command failed. Error = $err" if ($err > 0);
print "Succeeded\n";

#########
 
sub check_theskyx {
    open(PROC,"ps -ef|grep MacOS/TheSkyX|grep -v grep|");
    if ($ps_line = <PROC>){
        # TheSkyX is running. All is well.
        close(PROC);
        return;
    }
    else {
        # TheSkyX is not running, so start it
        print "Starting TheSkyX.\n";
        $has_rebooted = 1;
        system('nohup /Applications/TheSkyX\ Professional\ Edition.app/Contents/MacOS/TheSkyX > /dev/null &');
        sleep 15;

        `syslog -s -l alert [DragonflyEvent] mount.pl started TheSkyX`;

        close(PROC);
        return;
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
        $current += $wait_interval;
        Time::HiRes::sleep($wait_interval);
    }
    die "Mount.pl timed out" if ($current == $timeout);
    $line =~ /.*Error = (\d+)/;
    return $1;
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

mount - send a mount command to TheSkyX

=head1 SYNOPSIS

mount command [arguments]

=head1 ARGUMENTS

=over 8

=item B<command>

One of "goto", "dither", "home", "park", "position", "radec", "altaz", "start", "stop". These commands take arguments as follows:

 goto name
 dither arcmin direction
 home
 park
 position
 radec ra dec
 altaz alt az
 start
 stop

=back

=head1 OPTIONS

=over 8

=item B<--host IP>

IP address of the machine with the TheSkyX JavaScript command server. The default is
XXX.XXX.XXX.XXX

=item B<--[no]safe>          [default is --safe]

Check if the socket is blocked and if so force the use of Keyboard Maestro to send
commands.

=item B<--[no]maestro>           [default is --maestro]

Communicate via Keyboard Maestro rather than TCP. This is slow and relies on the 
Keyboard Maestro program being installed and running. It is currently active by
default (use --nomaestro to use TCP sockets instead).

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<mount> sends mount-control commands to TheSkyX. The SkyX's TCP server
appears to have intermittent blocking issues, so at the moment mount
control commands are sent using the Mac OS X Open Scripting Architecture
via the Keyboard Maestro helper program. This is pretty slow and
fragile but better than nothing.

=head1 EXAMPLES 

 % mount goto Jupiter
 % mount dither 15 N
 % mount position
 % mount home
 % mount park
 % mount start
 % mount --host localhost stop
 % mount radec "02h50m09s" "+35d57m55.0s"
 % mount altaz 34 122
 % mount --host localhost altaz 34 122

=cut

