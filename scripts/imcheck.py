#!/opt/local/bin/python2.7

import pyfits
import numpy as np
import pylab as py
import img_scale
import matplotlib.cm as cm
import glob
import os
import sys
import argparse
import subprocess
import string
from astropy.io import fits
import astropy.wcs as wcs

class ImageError(Exception):
    """Base class for exceptions in this module."""
    pass

class StampError(ImageError):
    """Raised when a postage stamp cannot be created.

    Attributes:
        msg  -- explanation of the error
    """
    def __init__(self, msg):
        self.msg = msg


def camera_subplot_index(filename):
    if   "83F010783" in filename:
        return 10
    elif "83F010826" in filename:
        return 7   
    elif "83F010820" in filename:
        return 8
    elif "83F010784" in filename:
        return 3
    elif "83F010827" in filename:
        return 4
    elif "83F010730" in filename:
        return 2
    elif "83F010687" in filename:
        return 9
    elif "83F010692" in filename:
        return 6 
    else:
        return -1;

# Parse command-line options
parser = argparse.ArgumentParser(description='Create postage stamp mosaic with stamps arraged in the physical geometry of the Dragonfly lenses.')
parser.add_argument("-v","--verbosity",help="increase output verbosity",action="store_true")
parser.add_argument("-m","--mail",help="email result to the Project Dragonfly account",action="store_true")
parser.add_argument('files',nargs='+', help='files to analyze')
args = parser.parse_args()

# Get image names from the command line
files = args.files
if not files:
    sys.stderr.write('Error: no files found')
    sys.exit(1)

# Load and process images
#small_images = []
#for this_image in files:
#    print "Processing %s" % this_image
#    tmp_img = pyfits.getdata(this_image)
#    tmp_img = tmp_img[1576:1776,1166:1366]
#    (sky,niter) = img_scale.sky_median_sig_clip(tmp_img,0.01,0.1,10)
#    small_images.append(img_scale.sqrt(tmp_img,scale_min=sky-100,scale_max=sky+5000))
 
small_images = []
for this_image in files:
    print "Processing %s" % this_image
    tmp_img = fits.open(this_image)
    data, h_original = tmp_img[0].data, tmp_img[0].header
    
    try:    
        # Does this frame have a WCS defined? If not it will throw a KeyError exception.
        check_wcs = h_original["CD1_1"]

        # Get the WCS data for the frame
        w_original = wcs.WCS(h_original)
        
        # Determine the X-Y position of the target
        nx, ny, target = h_original["naxis1"], h_original["naxis2"], h_original["target"]
        result = subprocess.Popen(["coords","-d",target], stdout=subprocess.PIPE)
        (sout,serr) = result.communicate()
        ra_target,dec_target = string.rstrip(sout).split( );
        ra_target=float(ra_target)
        dec_target=float(dec_target)
        #Note that i and j are reversed below because of the unusual astro image
        #convention for image order.
        [j, i], = w_original.wcs_world2pix([[ra_target, dec_target]], 1)
        i = int(i)
        j = int(j)
        print "target is at (%d,%d)" % (i,j)
        if (i<100 or j<100 or i>(nx-100) or j>(nx-100)):
            raise StampError()
        data = data[i-100:i+100,j-100:j+100]
        
    except KeyError:
        print "Image %s does not contain a WCS" % this_image
        data = data[1576:1776,1166:1366]
        
    except StampError:
        print "Image %s does not contain the target. The center of the image is being used instead." % this_image
        data = data[1576:1776,1166:1366]       
    
    (sky,niter) = img_scale.sky_median_sig_clip(data,0.01,0.1,10)
    small_images.append(img_scale.sqrt(data,scale_min=sky-100,scale_max=sky+5000))


# Define the canvas properties
fig = py.figure(figsize=(15,7.5))
fig.subplots_adjust(hspace = 0.15, wspace = 0, top=0.95, bottom=0.01, left=0.0,
        right=1.0)

# Render mosaic 
for index in range(len(files)):
    a = fig.add_subplot(2,5,camera_subplot_index(files[index]))
    py.axis('off')
    py.imshow(small_images[index],aspect='equal',cmap = cm.Greys)
    py.title(os.path.basename(files[index]))

# Save as a single image
py.savefig('/var/tmp/imcheck.jpg')

# Email results if requested
if args.mail:
    os.popen('mutt -s "postage stamps" -a /var/tmp/imcheck.jpg projectdragonfly@icloud.com < /dev/null').read();
    
