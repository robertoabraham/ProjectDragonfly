#!/bin/bash

username=`whoami`
find /Users/$username/Library/Application\ Support/Software\ Bisque/TheSkyX\ Professional\ Edition/Camera\ AutoSave/Autoguider -type f -name '*.log' -print0 | xargs -0 ls -tl | head -1 | awk '{ s = ""; for (i = 9; i <= NF; i++) s = s $i " "; print s}' | sed -e's/[[:space:]]*$//'  

