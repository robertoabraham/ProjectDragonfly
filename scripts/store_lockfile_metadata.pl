#!/opt/local/bin/perl

use Data::Dumper;
$verbose = 1;

open(LOCK,"</var/tmp/sbig.lock");

$ncamera = 0;
while(<LOCK>){
    chop;
    ( $dummy, $data{"PID"} )  = split( ':', $_) if (/^pid/);

    if (/^Working directory/) {
        ( $dummy, $dirname ) = split( ':', $_); 
        $dirname =~ s/\s//g;
        $data{"Directory"} = $dirname;    
    }

    if (/^Camera/){
        /(Camera )(\d)( wrote:)(.*)/;
        $camera_number = $2;
        $frame = $4;
        $frame =~ s/\s//g;
        $data{"Camera"}[$camera_number] = $frame;
        $ncamera++;
    }
}

for($i=0;$i<$ncamera;$i++) {
    $file = $data{"Directory"} . "/" . $data{"Camera"}[$i];
    print "Adding metadata to $file\n" if $verbose;
    `store_metadata $file`;
}


