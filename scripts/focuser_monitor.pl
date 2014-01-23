#!/usr/bin/perl

use Getopt::Long qw(:config require_order);  
use Pod::Usage;
use IO::Socket;

# Number of times to repeat commands
$max_attempts = 3;

# Map serial ports to lenses. 
$cameras=`camera_info lens focuser_port focus_start location | grep CanonEF400 | grep NewMexicoSkies`;
print "Monitoring focusers attached to these lenses:\n";
for (split /^/, $cameras) {
    chop;
    @data = split;
    $lens_id = $data[0];
    $focuser_port{$lens_id} = $data[2];
    $focuser_start{$lens_id} = $data[2];
    $serial_port{$lens_id} = $focuser_port{$lens_id};
    print "$lens_id\n";
}

#Parse command-line options
my $help = 0;
my $man = 0;
my $port = 7070;
my $echo = 0;
$result = GetOptions(
    "echo!" => \$echo,
"port=i" => \$port,
    "help|?" => \$help, 
man=> \$man) or pod2usage(2);
pod2usage(0) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

#Open socket
my $sock = new IO::Socket::INET (
#    LocalHost => '127.0.0.1',
    LocalPort => $port,
    Proto => 'tcp',
    Listen => 1,
    Reuse => 1,
);
die "Could not create socket: $!\n" unless $sock;

#Wait for commands
print "Focuser position server listening on port $port...\n";
$exe_bin = "/usr/local/bin";
while (my $connection = $sock->accept) {
    print "Client connected at ",scalar(localtime),"\n";
    # print $connection "Welcome to the Canon EF lens array server.\n";
    # handle the connection
    while(<$connection>){
        chop;
        ($lens,$command,$argument) = split;
        $command = "$command $argument";
        $command =~ s/\s+$//;

        if ($lens =~ /init/) {
            print "Client issues command $lens to all focusers attached to Canon EF lenses\n";
            # Special case! Send a general initialize command to all focusers 
            $cameras=`camera_info lens focuser_port focus_start location | grep CanonEF400 | grep NewMexicoSkies`;
            for (split /^/, $cameras) {
                chop;
                @data = split;
                $lens_id = $data[0];
                $focuser_port{$lens_id} = $data[2];

                # Obtain best guess at the focus position using a model
                my $info = `predict_focus $lens_id`;
                chop($info);
                $focuser_start{$lens_id} = $info;
                $bless{$lens_id} = 0; # All focusers start off cursed
            }
            my @cameras = keys(%focuser_start);
            foreach(@cameras) {
                my $n_tries = 1;
                print "Initializing focuser on camera $_ via serial port $focuser_port{$_} on the server computer\n";
                RETRY_INIT:
                $result=`$exe_bin/birger -p $serial_port{$_} init`;
                print $connection $result if length($result)>0;
                print "$result\n" if $echo;
                sleep(1);
                print "  Commanding focuser on camera $_ to go to its default focus position of $focuser_start{$_}\n";
                $result=`$exe_bin/birger -p $serial_port{$_} goto $focuser_start{$_}`;
                print $connection $result if length($result)>0;
                print "$result\n" if $echo;
                sleep(1);
                # Confirm it worked.
                $current_position{$_}=`$exe_bin/birger -p $serial_port{$_}`;
                chop($current_position{$_});
                print "  Focuser reports it is at $current_position{$_}\n";
                if ($current_position{$_}=="") {
                    $n_tries++;
                    if ($n_tries <= $max_attempts) {
                        print "Communications problem. Retrying...\n";
                        goto RETRY_INIT;
                    }
                    else {
                        print $connection "Error: Cannot communicate with focuser on CCD $_\n";
                    }
                }
                $check = abs($current_position{$_} - $focuser_start{$_});
                if ($check > 3) {
                    $n_tries++;
                    if ($n_tries <= $max_attempts) {
                        print "Movement problem. Retrying...\n";
                        goto RETRY_INIT;
                    }
                    else {
                        print $connection "Error: Focuser on camera $_ is not at its instructed setpoint.\n";
                    }
                }
                else {
                    print $connection "Initialization of focuser on camera $_ succeeded.\n";
                }
            }
            print $connection "Done.\n"; 
        }
        elsif ($lens =~ /bless/) {
            print "Client issues command $lens to all focusers attached to Canon EF lenses\n";
            # Special case! Send a general bless command to all focusers 
            $cameras=`camera_info lens focuser_port focus_start location | grep CanonEF400 | grep NewMexicoSkies`;
            for (split /^/, $cameras) {
                chop;
                @data = split;
                $lens_id = $data[0];
                $bless{$lens_id} = 1;
            }
            print $connection "Done.\n"; 
        }
        elsif ($lens =~ /curse/) {
            print "Client issues command $lens to all focusers attached to Canon EF lenses\n";
            # Special case! Send a general curse command to all focusers 
            $cameras=`camera_info lens focuser_port focus_start location | grep CanonEF400 | grep NewMexicoSkies`;
            for (split /^/, $cameras) {
                chop;
                @data = split;
                $lens_id = $data[0];
                $bless{$lens_id} = 0;
            }
            print $connection "Done.\n"; 
        }
        elsif ($lens =~ /predict/) {
            print "Client issues command $lens with argument \'$command\' to all focusers attached to Canon EF lenses\n";
            # Special case! Predict focus value for each nens
            $cameras=`camera_info lens focuser_port focus_start location | grep CanonEF400 | grep NewMexicoSkies`;
            for (split /^/, $cameras) {
                chop;
                @data = split;
                $lens_id = $data[0];
                $focuser_port{$lens_id} = $data[2];

                # Obtain best guess at the focus position using a model
                $temperature = $command;
                $tflag = "";
                $tflag = "-t $temperature" if ($temperature);
                $info = `predict_focus $tflag $lens_id`;
                $tsuccess = $?;
                if ($tsuccess == 0) {$tsuccess = "True"} else { $tsuccess = "False"};
                chop($info);
                $focuser_start{$lens_id} = $info;

                # Obtain current position
                $current=`$exe_bin/birger -p $serial_port{$lens_id}`;
                $fsuccess = $?;
                if ($fsuccess == 0) {$fsuccess = "True"} else { $fsuccess = "False"};
                chop($current);

                print $connection "Lens:$lens_id  PredictedFocus:$info CurrentPosition:$current TemperatureKnown:$tsuccess\n";
            }
            print $connection "Done.\n"; 
        }
        elsif ($lens =~ /status/) {
            print "Client issues command $lens with argument \'$command\' to all focusers attached to Canon EF lenses\n";
            # Special case! Summarize current state of the focusers
            $cameras=`camera_info lens focuser_port focus_start location | grep CanonEF400 | grep NewMexicoSkies`;
            for (split /^/, $cameras) {
                chop;
                @data = split;
                $lens_id = $data[0];
                $focuser_port{$lens_id} = $data[2];

                # Obtain current position
                $current=`$exe_bin/birger -p $serial_port{$lens_id}`;
                $fsuccess = $?;
                if ($fsuccess == 0) {$fsuccess = "True"} else { $fsuccess = "False"};
                chop($current);

                if (defined($bless{$lens_id})) {
                    print $connection "Lens:$lens_id  CurrentPosition:$current  PositionKnown:$fsuccess   Blessed:True\n" if $bless{$lens_id};
                    print $connection "Lens:$lens_id  CurrentPosition:$current  PositionKnown:$fsuccess   Blessed:False\n" if !($bless{$lens_id});
                }
                else {
                    print $connection "Lens:$lens_id  CurrentPosition:$current  PositionKnown:$fsuccess   Blessed:False\n";
                }
            }
            print $connection "Done.\n"; 
        }
        else {
            # General case! Send a command to a single focuser
            print "Client issues command '$command' to lens $lens\n";

            if ($command =~ /bless/c) {
                $bless{$lens} = 1;
                print $connection "Lens $lens blessed\n";
                print $connection "Done.\n"; 
            }
            elsif ($command =~ /curse/c) {
                $bless{$lens} = 0;
                print $connection "Lens $lens blessing revoked\n";
                print $connection "Done.\n"; 
            }
            else {

                if (defined($serial_port{$lens})) {
                    $n_tries = 0;
                    RETRY_GENERAL:
                    $result=`$exe_bin/birger -p $serial_port{$lens} $command`;
                    if ($? != 0) {
                        $n_tries++;
                        if ($n_tries <= $max_attempts) {
                            print "Retrying...\n";
                            goto RETRY_GENERAL;
                        }
                        else {
                            print $connection "Error: A general focuser error has occurred on CCD $_\n";
                        }
                    }
                    print $connection $result if length($result)>0;
                    print $connection "Done.\n"; 
                    print "$result\n" if $echo;
                }
                else {
                    print $connection "Error: Unknown lens number.\n";
                    print $connection "Done.\n"; 
                }

            }
        }
    }
    close $connection;
    print "Client disconnected\n";
}


__END__

=head1 NAME

focuser_monitor - focus control daemon

=head1 SYNOPSIS

focuser_monitor [OPTIONS] 

=head1 OPTIONS

=over 8

=item B<--port number>

Port to listen for commands on. The default is 7070.

=item B<--echo --noecho>

Display output from commands sent to the server. The default is --noecho.

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<focuser_monitor> controls a bank of focsers over a TCP/IP port.  It should be
run as a daemon process on whatever machine is physically connected to the
focusers. Multiple computers can send commands to the focuser server and the
requests will be serviced on a first-come first-served basis.  

The general syntax of commands is "lens_id birger_command [arguments]". In
addition, all lenses can be initialized to their default positions using the
special command "init", and predicted focus values can be obtained using the
special command "predict <temperature>".  If no temperature is supplied to the
"predict" command then the current temperature is assumed. Lenses can be
blessed to be in focus and ready to go with the "bless" command and they
can be flagged as being unready with the "curse" command.

Commands can be sent to the daemon in a myriad number of ways (e.g. using
telnet) though a particularly convenient way is to use the dragonfly command
B<df_send> which should already know the default TCP address and port number of
the focus server.
 
=head1 EXAMPLES

%df_send focusers "83F01687 goto 21700"

%df_send focusers "83F01687"

%df_send focusers "init"

%df_send focusers "predict"

%df_send focusers "predict 15"

%df_send focusers "status"

%df_send focusers "bless"

%df_send focusers "curse"

%df_send focusers "83F01687 bless"

%df_send focusers "83F01687 curse"

=cut

