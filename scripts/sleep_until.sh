#!/bin/bash

utc=$1

if [ -n "$1" ]
then
time_now=`date -u +%s`
time_obs=`date -j -u $utc +%s`
delay=`expr $time_obs - $time_now`
echo "sleeping until `date -j -u $utc` "
sleep $delay
fi