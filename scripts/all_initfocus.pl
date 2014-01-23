#!/opt/local/bin/perl

use DateTime;

$start_time = DateTime->now();

$log_message = "[DragonflyStatus] all_initfocus begun.";
`syslog -s -l alert $log_message`;
$result = `df_send focusers init`;
$log_message = "[DragonflyStatus] all_initfocus completed.";
`syslog -s -l alert $log_message`;
print "Result:\n";
print $result;

# Save the result to the log:
open(LOG,">/var/tmp/all_initfocus.txt");
$now = `date`;
chop($now);
print LOG "[$now]\n";
print LOG "$result";
close(LOG);

$end_time = DateTime->now();
$elapsed_time = ($end_time->subtract_datetime_absolute($start_time))->in_units('seconds');
print "Focusers initialized (took $elapsed_time seconds)\n";

# If an error occurred here it's pretty bad. So log it and email the users...
if ($result =~ /Error/) {
    $error_message = "[DragonflyError] all_initfocus failed to initialize one or more focusers";
    `syslog -s -l alert $error_message`;
    `mutt -s "$error_message" projectdragonfly\@icloud.com < /var/tmp/all_initfocus.txt`;
    print "$error_message\n";
}

exit(0);

