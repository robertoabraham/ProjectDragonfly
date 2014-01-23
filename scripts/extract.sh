#!/bin/sh
#
# NAME
#      extract - Determine statistical properties of a FITS image
# 
# USAGE 
#      extract [-z zeropoint] [-p pixelscale] <fitsFilename> 
#
# DESCRIPTION
#
# AUTHOR 
#      R.G. Abraham (abraham@astro.utoronto.ca)
# DATE 
#      April 2011


 usage()
{ echo " "
  echo "NAME"
  echo "     extract --- Determine statistical properties of a FITS image"
  echo " "
  echo "SYNOPSIS"
  echo "     extract [options...] filename"
  echo " "
  echo "DESCRIPTION"
  echo "     extract is intended to be a friendly front-end to SExtractor."
  echo " "
  echo "OPTIONS"
  echo "     -z  zeropoint       # Default set to 25.0"
  echo "     -p  pixelscale      # Default set to 2.8"
  echo "     -D                  # Create debug directory"
  echo "     -s                  # Use 500x500 susbet [1400:1899,1000:1499]"
  echo "     -S                  # Create catalog suitable for use by Scamp"
  echo "     -B                  # Find bright objects only"
  echo "     -h                  # Print usage information"
  echo " "
  exit 1
}


#Default values

zeropoint=25.0
pixelscale=2.84
detectminarea=5
detectthresh=1.5
analyzethresh=1.5
deblendthresh=32
deblendmincont=0.005
seeing=5.0
gain=1.0
convoption=1
debug=0
subset=0
scamp=0
bright=0
catalogtype="ASCII_HEAD"
subregion=""

while getopts "z:p:DBsSh" options; do
  case $options in
    z ) zeropoint=$OPTARG;;
    p ) pixelscale=$OPTARG;;
    s ) subset=1;;
    S ) scamp=1;;
    D ) debug=1;;
    B ) bright=1;;
    h ) usage;;
    \? ) usage
         exit 1;;
    * ) usage
          exit 1;;

  esac
done

shift $(($OPTIND - 1))

if test $# = 0
    then
    echo " "
    usage
    echo " "
    exit
fi

if [ $subset == 1 ]
then
    subregion="[1400:1899,1000:1499]"
fi

if [ $scamp == 1 ]
then
    catalogtype="FITS_LDAC"
fi


if [ $bright == 1 ]
then
    detectthresh=20
fi


# extract the filename (without .fits extension) from a fully specified path
filename_with_path=$1
filename=${filename_with_path##*/}
path=${filename_with_path%/*}
fileroot=${filename%.fits}

###### CREATE TEMPORARY TEXT FILES USED BY SEXTRACTOR ######

# Create the .conv convolution kernel (this is a 3x3 default)
CONV="$(mktemp /var/tmp/conv.XXXXXX)"
if [ ${convoption} -eq 1 ]
then
cat > $CONV <<- EndOfConvFile
	CONV NORM
	# 3x3 "all-ground" convolution mask with FWHM = 2.0 pixels.
	1.0000 2.0000 1.0000
	2.0000 4.0000 2.0000
	1.0000 2.0000 1.0000
EndOfConvFile
else
cat > $CONV <<- EndOfConvFile
        CONV NORM
        # 3x3 convolution mask of a top-hat PSF with diameter = 3.0 pixels.
        0.560000 0.980000 0.560000
        0.980000 1.000000 0.980000
        0.560000 0.980000 0.560000
EndOfConvFile
fi

# Create the .nnw file specifying the neural network weights
NNW="$(mktemp /var/tmp/nnw.XXXXXX)"
cat > $NNW <<- EndOfNNWFile
	NNW
	# Neural Network Weights for the SExtractor star/galaxy classifier (V1.3)
	# inputs:       9 for profile parameters + 1 for seeing.
	# outputs:      ``Stellarity index'' (0.0 to 1.0)
	# Seeing FWHM range: from 0.025 to 5.5'' (images must have 1.5 < FWHM < 5 pixels)
	# Optimized for Moffat profiles with 2<= beta <= 4.
	
	 3 10 10  1
	
	-1.56604e+00 -2.48265e+00 -1.44564e+00 -1.24675e+00 -9.44913e-01 -5.22453e-01  4.61342e-02  8.31957e-01  2.15505e+00  2.64769e-01
	 3.03477e+00  2.69561e+00  3.16188e+00  3.34497e+00  3.51885e+00  3.65570e+00  3.74856e+00  3.84541e+00  4.22811e+00  3.27734e+00
	
	-3.22480e-01 -2.12804e+00  6.50750e-01 -1.11242e+00 -1.40683e+00 -1.55944e+00 -1.84558e+00 -1.18946e-01  5.52395e-01 -4.36564e-01 -5.30052e+00
	 4.62594e-01 -3.29127e+00  1.10950e+00 -6.01857e-01  1.29492e-01  1.42290e+00  2.90741e+00  2.44058e+00 -9.19118e-01  8.42851e-01 -4.69824e+00
	-2.57424e+00  8.96469e-01  8.34775e-01  2.18845e+00  2.46526e+00  8.60878e-02 -6.88080e-01 -1.33623e-02  9.30403e-02  1.64942e+00 -1.01231e+00
	 4.81041e+00  1.53747e+00 -1.12216e+00 -3.16008e+00 -1.67404e+00 -1.75767e+00 -1.29310e+00  5.59549e-01  8.08468e-01 -1.01592e-02 -7.54052e+00
	 1.01933e+01 -2.09484e+01 -1.07426e+00  9.87912e-01  6.05210e-01 -6.04535e-02 -5.87826e-01 -7.94117e-01 -4.89190e-01 -8.12710e-02 -2.07067e+01
	-5.31793e+00  7.94240e+00 -4.64165e+00 -4.37436e+00 -1.55417e+00  7.54368e-01  1.09608e+00  1.45967e+00  1.62946e+00 -1.01301e+00  1.13514e-01
	 2.20336e-01  1.70056e+00 -5.20105e-01 -4.28330e-01  1.57258e-03 -3.36502e-01 -8.18568e-02 -7.16163e+00  8.23195e+00 -1.71561e-02 -1.13749e+01
	 3.75075e+00  7.25399e+00 -1.75325e+00 -2.68814e+00 -3.71128e+00 -4.62933e+00 -2.13747e+00 -1.89186e-01  1.29122e+00 -7.49380e-01  6.71712e-01
	-8.41923e-01  4.64997e+00  5.65808e-01 -3.08277e-01 -1.01687e+00  1.73127e-01 -8.92130e-01  1.89044e+00 -2.75543e-01 -7.72828e-01  5.36745e-01
	-3.65598e+00  7.56997e+00 -3.76373e+00 -1.74542e+00 -1.37540e-01 -5.55400e-01 -1.59195e-01  1.27910e-01  1.91906e+00  1.42119e+00 -4.35502e+00
	
	-1.70059e+00 -3.65695e+00  1.22367e+00 -5.74367e-01 -3.29571e+00  2.46316e+00  5.22353e+00  2.42038e+00  1.22919e+00 -9.22250e-01 -2.32028e+00
	
	
	 0.00000e+00 
	 1.00000e+00 
EndOfNNWFile

# Create the .param file specifying what gets output by SExtractor.
PARAM="$(mktemp /var/tmp/param.XXXXXX)"
cat > $PARAM <<- EndOfParamFile
	NUMBER
	X_IMAGE
	Y_IMAGE
    FLUX_ISO
    FLUXERR_ISO
    FWHM_IMAGE
    ELONGATION
    ELLIPTICITY
	BACKGROUND
	MAG_AUTO
	MAGERR_AUTO
	THRESHOLD
	CLASS_STAR
	FLAGS
	A_IMAGE
	B_IMAGE
	THETA_IMAGE
	ISOAREA_IMAGE
	FLUX_MAX
#	MU_THRESHOLD
#	MU_MAX
	XWIN_IMAGE
	YWIN_IMAGE
	ERRAWIN_IMAGE
	ERRBWIN_IMAGE
	ERRTHETAWIN_IMAGE
	FLUX_AUTO
	FLUXERR_AUTO
    FLUX_RADIUS
#	XMIN_IMAGE
#	YMIN_IMAGE
#	XMAX_IMAGE
#	YMAX_IMAGE
#   X_WORLD
#   Y_WORLD
#	XPEAK_IMAGE
#	YPEAK_IMAGE
	ALPHA_J2000
	DELTA_J2000
#	X2_IMAGE
#	Y2_IMAGE
#	XY_IMAGE
#   X2_WORLD
#   Y2_WORLD
#   XY_WORLD
#   A_WORLD
#   B_WORLD
#   THETA_WORLD
EndOfParamFile


# Create the .sex file specifying the extraction settings. Note that the weight image
# is explicitly specified later on the command-line call to SExtractor.
CATALOG="$(mktemp /var/tmp/catalog.XXXXXX)"
SETTINGS="$(mktemp /var/tmp/settings.XXXXXX)"
cat > $SETTINGS <<- EndOfSexFile
	ANALYSIS_THRESH ${analyzethresh}
	BACK_FILTERSIZE 3
	BACKPHOTO_TYPE GLOBAL
	BACK_SIZE 128
	CATALOG_NAME $CATALOG
	CATALOG_TYPE $catalogtype
	CLEAN Y
	CLEAN_PARAM 1.
	DEBLEND_MINCONT $deblendmincont
	DEBLEND_NTHRESH $deblendthresh
	DETECT_MINAREA $detectminarea
	DETECT_THRESH $detectthresh 
	DETECT_TYPE CCD
	FILTER Y
	FILTER_NAME $CONV
	FLAG_IMAGE flag.fits
	GAIN $gain
	MAG_GAMMA 4.
	MAG_ZEROPOINT $zeropoint
	MASK_TYPE CORRECT
	MEMORY_BUFSIZE 1024
	MEMORY_OBJSTACK 3000
	MEMORY_PIXSTACK 300000
	PARAMETERS_NAME $PARAM 
	PHOT_APERTURES 5
	PHOT_AUTOPARAMS 2.5, 3.5
	PIXEL_SCALE $pixelscale
	SATUR_LEVEL 50000.
	SEEING_FWHM ${seeing}
	STARNNW_NAME $NNW
	VERBOSE_TYPE QUIET
EndOfSexFile

###### ANALYSIS BEGINS HERE ######

IMAGE="$(mktemp /var/tmp/fitsimage.XXXXXX)"
fitscopy "${filename_with_path}$subregion" "!$IMAGE"
/opt/local/bin/sex $IMAGE -c $SETTINGS -PARAMETERS_NAME $PARAM
cat $CATALOG

# Remove temporary files.
rm -f $IMAGE
rm -f $CATALOG
rm -f $SETTINGS
rm -f $PARAM
rm -f $NNW
rm -f $CONV
