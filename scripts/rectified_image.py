#!/opt/local/bin/python2.7

import argparse
import matplotlib.pyplot as plt
import matplotlib.cm as cm
import os
import img_scale
import numpy as np
import astropy.wcs as wcs
from astropy.io import fits
import pywcsgrid2

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
this_image = files[0]
print "Processing %s" %this_image
f = fits.open(this_image)
d, h2 = f[0].data, f[0].header

# Rescale the image
(sky,niter) = img_scale.sky_median_sig_clip(d,0.01,0.1,10)
processed_image = img_scale.sqrt(d,scale_min=sky-300,scale_max=sky+10000)

# Get basic data in the original frame
w2 = wcs.WCS(h2)

# To make the rotation easier, first shift the WCS reference pixel to
# the center of the grid
nx, ny = h2["naxis1"], h2["naxis2"]
i0, j0 = (float(nx) + 1.0)/2, (float(ny) + 1.0)/2
[ra0, dec0], = w2.wcs_pix2world([[i0, j0]], 1)
h2.update(crpix1=i0, crpix2=j0, crval1=ra0, crval2=dec0)

# Now construct a header that is in the equatorial frame (North up, east to the left)
h1 = h2.copy()
h1.update(
    cd1_1=-np.hypot(h2["CD1_1"], h2["CD1_2"]), 
    cd1_2=0.0, 
    cd2_1=0.0, 
    cd2_2=np.hypot(h2["CD2_1"], h2["CD2_2"]), 
    orientat=0.0)

# Finally plot the image in the new frame
arcsec = 1./3600
ax = pywcsgrid2.axes(wcs=h1, aspect=1)
#ax.set_xlim(-nx/4, 5*nx/4)
#ax.set_ylim(-ny/4, 5*ny/4)
ax.set_xlim(-nx/8, 9*nx/8)
ax.set_ylim(-ny/4, 5*ny/4)
# Mark a line in red
# ax["fk5"].plot([ra0, ra0], [dec0 + 10*arcsec, dec0 + 15*arcsec], "r")
ax.locator_params(axis="x", nbins=5)
ax.locator_params(axis="y", nbins=5)
ax[h2].imshow_affine(processed_image, origin='lower', cmap=plt.cm.gray_r)
ax.grid()
#ax.figure.savefig("/var/tmp/nice_image.pdf", dpi=150)
ax.figure.savefig("/var/tmp/nice_image.png")

# Email results if requested
if args.mail:
    os.popen('mutt -s "Full field image" -a /var/tmp/nice_image.png projectdragonfly@icloud.com < /dev/null').read();
    
