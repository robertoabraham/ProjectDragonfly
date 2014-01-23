#!/bin/bash

 usage()
{ echo " "
  echo "NAME"
  echo "     tskip --- skip a number of rows in a table"
  echo " "
  echo "SYNOPSIS"
  echo "     tskip [options] number < file"
  echo " "
  echo "DESCRIPTION"
  echo "     tskip removes a number of lines from the front of a data table"
  echo " "
  echo "OPTIONS"
  echo "     -r                  # Do not print the header"
  echo "     -h                  # Print usage information"
  echo " "
  exit 1
}

print_header=true
while getopts "rh" options; do
  case $options in
    r ) print_header=false;;
    h ) usage
        exit 1;;
    * ) usage
        exit 1;;
  esac
done
shift $(($OPTIND - 1))

if [ $# -eq 0 ] ; then
    echo 'tskip [-r -h] num < catalog'
    exit 0
fi
nrow=$(expr $1 + 1)

tempbase=`basename $0`
TMP_INPUT=`mktemp /var/tmp/${tempbase}.XXXXXX` || exit 1
TMP_HEADER_FILE=`mktemp /var/tmp/${tempbase}.XXXXXX` || exit 1
TMP_DATA_FILE=`mktemp /var/tmp/${tempbase}.XXXXXX` || exit 1

# store the header and data in a temporary file
cat /dev/stdin > $TMP_INPUT
cat $TMP_INPUT | grep '^#' > $TMP_HEADER_FILE
cat $TMP_INPUT | grep -v '^#' | tail -n +$nrow > $TMP_DATA_FILE

if [ $print_header ]; then
    cat $TMP_HEADER_FILE
fi
cat $TMP_DATA_FILE

rm -f $TMP_INPUT_FILE
rm -f $TMP_HEADER_FILE
rm -f $TMP_DATA_FILE

exit 0
