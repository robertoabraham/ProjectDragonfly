#!/usr/bin/perl

use Getopt::Long qw(:config require_order);  
use Pod::Usage;

# Parse command-line options
my $man = 0;
my $help = 0;
my $dataset = 0;
$result = GetOptions(
    "help|?" => \$help, 
     man=> \$man) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus =>0, -verbose =>2) if $man;

@data = <STDIN>;

$index = 0;
for($i=0;$i<@data;$i++) {
    $row = $data[$i];
    if ($row =~ /^\|.+\d/) {
        @col = split(/\|/,$row);
        $ElapsedSecs[$index]  = $col[1];
        $RefCentroidX[$index] = $col[2];
        $RefCentroidY[$index] = $col[3];
        $CurCentroidX[$index] = $col[4];
        $CurCentroidY[$index] = $col[5];
        $GuideErrX[$index]    = $col[6];
        $GuideErrY[$index]    = $col[7];
        $TotGuideErr[$index]  = $col[8];
        $XPlusRelay[$index]   = $col[9];
        $XMinusRelay[$index]  = $col[10];
        $YPlusRelay[$index]   = $col[11];
        $YMinusRelay[$index]  = $col[12];
        $PECIndexRA[$index]   = $col[13];
        $PECIndexDec[$index]  = $col[14];

        $index++;
    }

}

print "# 1 ElapsedSecs\n";
print "# 2 RefCentroidX\n";
print "# 3 RefCentroidY\n";
print "# 4 CurCentroidX\n";
print "# 5 CurCentroidY\n";
print "# 6 GuideErrX\n";
print "# 7 GuideErrY\n";
print "# 8 TotGuideErr\n";
print "# 9 XPlusRelay\n";
print "# 10 XMinusRelay\n";
print "# 11 YPlusRelay\n";
print "# 12 YMinusRelay\n";
print "# 13 PecIndexRA\n";
print "# 14 PecIndexDec\n";

for ($i=0;$i<$index;$i++){
    printf("%10f %10f %10f %10f %10f %10f %10f %10f %10f %10d %10d %10d %10d %10d \n",
        $ElapsedSecs[$i],
        $RefCentroidX[$i],
        $RefCentroidY[$i],
        $CurCentroidX[$i],
        $CurCentroidY[$i],
        $GuideErrX[$i],
        $GuideErrY[$i],
        $TotGuideErr[$i],
        $XPlusRelay[$i],
        $XMinusRelay[$i],
        $YPlusRelay[$i],
        $YMinusRelay[$i],
        $PECIndexRA[$i],
        $PECIndexDec[$i]);
}
    

__END__

=head1 NAME

guider_log_table - convert TheSkyX guiding log to standard table format

=head1 SYNOPSIS

guider_log_table [options] < log.txt

options:

 --help
 --man

=head1 Options

=over 8

=item B<-help>

Prints a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<guider_log_table> converts a TheSkyX autoguider log
into a SExtractor format table.

=head1 EXAMPLES

guider_log_table < log.txt 

=cut

