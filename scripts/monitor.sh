#!/bin/bash

# echo
while [ 1 ]
do
    # The next echo statement  makes each status update overwrite the previous one. Be sure to
    # uncomment the echo statement above too.
    # echo -ne "\033[1A"
    echo `status | tail -1`
    sleep 3
done
