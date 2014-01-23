#!/opt/local/bin/perl

# Parse arguments
my $temperature = $ARGV[0];

# Determine the IP addresses of the computers hosting cameras
$ip=`camera_info host lens location status | grep NewMexicoSkies | grep Nominal | awk '{print \$2}' | sort | uniq | tr '\n' ' '`;
@ip = split('\s+',$ip);

foreach(@ip) {
    print "[$_] Setting temperature to $temperature\n";
    `send $_ 7078 "regulate $temperature"`;
    $result=`send $_ 7078 pwd`;
}

exit(0);

