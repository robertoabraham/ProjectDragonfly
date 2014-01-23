Software to control the Dragonfly Telephoto Array
(c) 2014 R. Abraham and P. van Dokkum

We strongly recommend that before you try to use this software for anything
non-trivial you contact either Bob Abraham or Pieter van Dokkum for an
explanation of how stuff works, lest you go insane. Also, do check out the
Abraham & van Dokkum 2014 PASP paper which provides some background.  You will
find that documentation for the Dragonfly software is pretty sparse, but all of
the really important scripts have quite comprehensive on-line help (for the
perl scripts use the --man or --help options to see this).  

Certain bits of the code in this repo have been "sanitized" to remove
hard-coded static IP addresses.  These will be obvious in the code since IP
addresses have been replaced by a series of "X" characters, e.g.
XXX.XXX.XXX.XXX. You will need to replace these with the static IP addresses of
the various things on your network.
