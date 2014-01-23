#!/bin/bash

# TCOLUMN - cuts out named columns from a SExtractor text catalog.
#
# OPTIONS
#    -H  Print SExtractor-style header
#
# This script operates on a stdin data stream. For example:
#
# extract ../../dat/foo.fits | tcolumn X_IMAGE Y_IMAGE FWHM_IMAGE 
#
# If you wish to use it with a catalog file use input redirection.
# For example:
#
# extract ../../dat/foo.fits > catalog.txt
# tcolumn FWHM_IMAGE NUMBER FLUX_ISO <catalog.txt 

print_header=false
while getopts "H" options; do
  case $options in
    H ) print_header=true;;
    * ) break;;
  esac
done
shift $(($OPTIND - 1))

tempbase=`basename $0`
TMP_AWK_FILE=`mktemp /var/tmp/${tempbase}.XXXXXX` || exit 1
TMP_CATALOG_FILE=`mktemp /var/tmp/${tempbase}.XXXXXX` || exit 1

# Filter comments from input before any processing
cat /dev/stdin | grep -v '#!' > $TMP_CATALOG_FILE

nhead=`grep '#' $TMP_CATALOG_FILE | wc | awk '{print \$1}'`
ncol=0  
while true; do
	if [ $1 ]; then
        colname[$ncol]=$1
        colnumber[$ncol]=`grep $1 $TMP_CATALOG_FILE | awk '{print \$2}'`
        coldesc[$ncol]=`head -n17 $TMP_CATALOG_FILE | grep $1`;
		shift
	else
		break # Stop loop when no more args.
	fi
	ncol=$((ncol+1))
done

if [ ${print_header} = true ]; then
    for i in $(seq 0 $((ncol-1)))
    do
        echo ${coldesc[$i]}
    done
fi

command="{print "
for i in $(seq 0 $((ncol-1)))
do
    command=$command"\$"${colnumber[$i]}
    command=$command","
done
command="${command%?}""}"
echo $command > $TMP_AWK_FILE

#echo "`grep -v '#' $TMP_CATALOG_FILE | awk -f $TMP_AWK_FILE | grep -v '^\$'`"
grep -v '#' $TMP_CATALOG_FILE | awk -f $TMP_AWK_FILE | grep -v '\^\$'

rm -f $TMP_AWK_FILE
rm -f $TMP_CATALOG_FILE

exit 0
