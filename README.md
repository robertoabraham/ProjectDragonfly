Software to control the Dragonfly Telephoto Array
(c) 2014 R. Abraham and P. van Dokkum

We strongly recommend that before you try to use this software for anything
non-trivial you contact either Bob Abraham or Pieter van Dokkum for an
explanation of how stuff works, lest you go insane. Also, do check out the
Abraham & van Dokkum 2014 PASP paper which provides some background.  You will
find that documentation for the Dragonfly software is pretty sparse, but all of
the really important scripts have quite comprehensive on-line help (for the
perl scripts use the --man or --help options to see this).  

Certain bits of the code in this repo have been sanitized in order to maintain
the security of the New Mexico Skies observatory. The main thing we have done
is remove all the hard-coded static IP addresses from the scripts.  The places
where we have done this will be obvious in the code, since IP addresses have
been replaced by a series of "X" characters, e.g. XXX.XXX.XXX.XXX. You will
need to replace these with the static IP addresses of the various things on
your network. We also have omitted a number of scripts which control the power
on the peripherals, and which access the various environmental sensors and
all-sky cameras in the observatory. 
