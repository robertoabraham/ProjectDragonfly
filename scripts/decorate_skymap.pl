#!/opt/local/bin/perl

use GD;
use GD::Polyline;

# Get command-line arguments
my $alt = shift;
my $az = shift;

# Conversion from alt-az to X-Y... this takes many steps
my $lambda0 = 0.0;
my $phi0 = 90*3.14159/180.0;
my $R = 320;
my $x0 = 320;
my $y0 = 240;

# Convert from degrees to radians in the correct direction
my $az_r = -1.0 * $az * 3.14159/180.0;
my $alt_r = $alt * 3.14159/180.0;

# Convert Alt-Az to X-Y 

# Orthographic - looks weird for wide angles but here for completeness. See
# http://en.wikipedia.org/wiki/Orthographic_projection_(cartography)
# my $x = $x0 + $R * cos($alt_r) * sin($az_r - $lambda0);
# my $y = $y0 + $R * (cos($phi0)*sin($alt_r) - sin($phi0)*cos($alt_r)*cos($az_r-$lambda0));

# Stereographic - best for all-sky maps. See
# http://mathworld.wolfram.com/StereographicProjection.html
my $k = $R/(1+sin($phi0)*sin($alt_r) + cos($phi0)*cos($alt_r)*cos($az_r-$lambda0));
my $x = $x0 + $k * cos($alt_r) * sin($az_r - $lambda0);
my $y = $y0 + $k * (cos($phi0)*sin($alt_r) - sin($phi0)*cos($alt_r)*cos($az_r-$lambda0));


print "Target X,Y = ($x,", ",$y,", ")\n" if $verbose;

# load the image
`rm -f /var/tmp/all_sky.jpg`;
`curl -s http://newmexicoskies.com/images/AllSkyImage.jpg > /var/tmp/all_sky.jpg`;
my $input_jpg = "/var/tmp/all_sky.jpg";
my $input_jpg = "/users/dragonfly/Desktop/AllSkyImage.jpg";
my $im = newFromJpeg GD::Image($input_jpg);

# draw a semicircle centered at the desired position
my $red = $im->colorAllocateAlpha(255,0,0,255); #background color
my $yellow = $im->colorAllocateAlpha(255,255,0,255);
my $poly = new GD::Polyline;
my $thickness = 2;
$im->setThickness($thickness);
$poly->addPt($x-5,$y);
$poly->addPt($x-10,$y);
$im->polydraw($poly,$yellow);
$poly->clear();
$poly->addPt($x+5,$y);
$poly->addPt($x+10,$y);
$im->polydraw($poly,$yellow);
$poly->clear();
$poly->addPt($x,$y-5);
$poly->addPt($x,$y-10);
$im->polydraw($poly,$yellow);
$poly->clear();
$poly->addPt($x,$y+5);
$poly->addPt($x,$y+10);
$im->polydraw($poly,$yellow);


open(OUTPUT,">/var/tmp/decorated_all_sky.jpg");
binmode OUTPUT;
print OUTPUT $im->jpeg;
close(OUTPUT);

print "Decorated image stored in /var/tmp/decorated_all_sky.jpg\n";

exit(0);

