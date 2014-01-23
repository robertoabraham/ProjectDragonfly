#!/opt/local/bin/python2.7

import argparse
import matplotlib.pyplot as plt
import matplotlib.cm as cm
import os
import subprocess
import string
import math
import img_scale
import sys
import numpy as np
import astropy.wcs as wcs
from astropy.io import fits
import pywcsgrid2

# Some handy constants
arcsec = 1./3600
arcmin = 1./60

# Parse command-line options
parser = argparse.ArgumentParser(description='Create a nicely labeled image of a Dragonfly image.')
parser.add_argument("-v","--verbosity",help="increase output verbosity",action="store_true")
parser.add_argument("-m","--mail",help="email result to the Project Dragonfly account",action="store_true")
parser.add_argument('files',nargs='+', help='files to analyze')
args = parser.parse_args()

# Get image names from the command line
files = args.files
if not files:
    sys.stderr.write('Error: no files found')
    sys.exit(1)

# Load the image
grayscale_drawn = False
for this_image in files:
    print "Processing %s" %this_image
    f = fits.open(this_image)
    data, h_original = f[0].data, f[0].header
    
    try:    
        # Does this frame have a WCS defined? If not it will throw a KeyError which we catch.
        check_wcs = h_original["CD1_1"]

        # Get the WCS data for the original (rotated) frame
        w_original = wcs.WCS(h_original)

        # To make the later rotation to North-up easier, first shift the WCS reference pixel to
        # the center of the grid
        nx, ny = h_original["naxis1"], h_original["naxis2"]
        i0, j0 = (float(nx) + 1.0)/2, (float(ny) + 1.0)/2
        [ra0, dec0], = w_original.wcs_pix2world([[i0, j0]], 1)
        h_original.update(crpix1=i0, crpix2=j0, crval1=ra0, crval2=dec0)

        # Now construct a header that is in the equatorial frame (North up, east to the left)
        h_equatorial = h_original.copy()
        h_equatorial.update(
            cd1_1=-np.hypot(h_original["CD1_1"], h_original["CD1_2"]), 
            cd1_2=0.0, 
            cd2_1=0.0, 
            cd2_2=np.hypot(h_original["CD2_1"], h_original["CD2_2"]), 
            orientat=0.0)


        if not grayscale_drawn:
            
            # Define the axis limits if this is the first frame with a valid WCS. This
            # first frame defines the axes for all subsequent drawing.
            ax = pywcsgrid2.axes(wcs=h_equatorial, aspect=1)
            ax.set_xlim(-nx/8, 9*nx/8)
            ax.set_ylim(-ny/4, 5*ny/4)
            ax.locator_params(axis="x", nbins=5)
            ax.locator_params(axis="y", nbins=5)
            target = h_original["target"]
            ax.set_title(this_image)
            
            # Mark the target as a crosshair in red
            result = subprocess.Popen(["coords","-d",target], stdout=subprocess.PIPE)
            (sout,serr) = result.communicate()
            ra_target,dec_target = string.rstrip(sout).split( );
            ra_target = float(ra_target)
            dec_target = float(dec_target)
            cd=math.cos(dec_target*3.14159/180.) 
            ax["fk5"].plot([ra_target+6*arcmin, ra_target+10*arcmin], [dec_target, dec_target], "r")
            ax["fk5"].plot([ra_target-6*arcmin, ra_target-10*arcmin], [dec_target, dec_target], "r")
            ax["fk5"].plot([ra_target, ra_target], [dec_target+6*arcmin*cd, dec_target+10*arcmin*cd], "r")
            ax["fk5"].plot([ra_target, ra_target], [dec_target-6*arcmin*cd, dec_target-10*arcmin*cd], "r")
            
            # annotate the target
            from matplotlib.patheffects import withStroke
            myeffect = withStroke(foreground="w", linewidth=0)
            kwargs = dict(path_effects=[myeffect])
            ax["fk5"].annotate((target.replace("_"," ")), (ra_target-13*arcmin,dec_target), size=8, ha="left", va="center", **kwargs)
            
            # draw the image
            (sky,niter) = img_scale.sky_median_sig_clip(data,0.01,0.1,10)
            scaled_data = img_scale.sqrt(data,scale_min=sky-300,scale_max=sky+10000)
            ax[h_original].imshow_affine(scaled_data, origin='lower', cmap=plt.cm.gray_r)
            ax.grid()
            grayscale_drawn = True


        # Outline the frame limits. This gets done for all frames.
        i_a, j_a = (0.0 + 1.0), (0.0 + 1.0)
        [ra_a, dec_a], = w_original.wcs_pix2world([[i_a, j_a]], 1)

        i_b, j_b = (float(nx) + 1.0), (0 + 1.0)
        [ra_b, dec_b], = w_original.wcs_pix2world([[i_b, j_b]], 1)

        i_c, j_c = (float(nx) + 1.0), (float(ny) + 1.0)
        [ra_c, dec_c], = w_original.wcs_pix2world([[i_c, j_c]], 1)

        i_d, j_d = (0.0 + 1.0), (float(ny) + 1.0)
        [ra_d, dec_d], = w_original.wcs_pix2world([[i_d, j_d]], 1)

        ax["fk5"].plot([ra_a, ra_b], [dec_a, dec_b], "k")
        ax["fk5"].plot([ra_b, ra_c], [dec_b, dec_c], "k")
        ax["fk5"].plot([ra_c, ra_d], [dec_c, dec_d], "k")
        ax["fk5"].plot([ra_d, ra_a], [dec_d, dec_a], "k")
        
    except KeyError:
        print "Image %s does not contain a WCS" % this_image


# Save the image for posterity
print "Saving figure to /var/tmp/nice_image.png"
ax.figure.savefig("/var/tmp/nice_image.png")

# Email results if requested
if args.mail:
    os.popen('mutt -s "Full field image" -a /var/tmp/nice_image.png projectdragonfly@icloud.com < /dev/null').read();
    
