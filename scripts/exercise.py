#!/opt/local/bin/python2.7

import ephem
import math
import random
import time
import subprocess
import string
import os
import shutil
import argparse
import signal
import sys

class Log:
    """Record of slew information
    
    Attributes:
        nbadslew    -- number of slew errors
        nbaddither  -- number of pointing errors 
        nbadguide   -- number of failed attempts to guide
        slewtimes   -- array of times in second for each slew
        errortimes  -- array of times error occurred
        dithertimes -- array of times in second for each dither
    """
    nbadslew = 0
    nbaddither = 0
    nbadguide = 0
    slewtimes = []
    errortimes = []
    dithertimes = []
    badstars = []

    def addbadslew(self):
        self.nbadslew = self.nbadslew + 1;

    def addbaddither(self):
        self.nbaddither = self.nbaddither + 1;

    def addbadguide(self):
        self.nbadguide = self.nbadguide + 1;

    def addbadstar(self,name):
        self.badstars.append(name);

    def adderrortime(self,thetime):
        self.errortimes.append(thetime);

    def addslew(self,time):
        self.slewtimes.append(time);

    def adddither(self,time):
        self.dithertimes.append(time);


class PointingError(Exception):
    """Base class for exceptions in this module."""
    pass

class SlewError(PointingError):
    """Raised when a slew generates an error.

    Attributes:
        name -- name of the star being slewed to
        msg -- explanation of the error
    """
    def __init__(self, name, msg):
        self.name = name
        self.msg = msg

class DitherError(PointingError):
    """Raised when a dither generates an error.

    Attributes:
        name -- name of the star being dithered around
        msg -- explanation of the error
    """
    def __init__(self, name, msg):
        self.name = name
        self.msg = msg

class GuideError(PointingError):
    """Raised when guiding generates an error.

    Attributes:
        name -- name of the star being guided around
        msg -- explanation of the error
    """
    def __init__(self, name, msg):
        self.name = name
        self.msg = msg

def SlewScope(star,log,location,dither,guide,maestro,safe):

    guide_time = 30

    # If the user has hit a ^C just pass through
    global exit_now
    if exit_now:
        return 1

    ra=star.ra*180/math.pi/15.0
    dec=star.dec*180/math.pi
    lst = location.sidereal_time() 
    ha = (lst - star.ra)*180/math.pi/15.0
    if (ha < -12.0):
        ha = 24.0 + ha
    directions = ["N","S","E","W"]
    try:
        print "Slewing to %s" % star.name
        print "  RA:  %s" % star.ra
        print "  LST: %s" % lst
        print "  HA:  %f" % ha
        tic = time.time()
        if maestro:
            protocol = "--maestro" 
        else:
            protocol = "--nomaestro"
        if safe:
            safety = "--safe"
        else:
            safety = "--nosafe"
        proc = subprocess.Popen(["mount",protocol,safety,"--noverbose","--host","localhost","goto",star.name], stdout=subprocess.PIPE)
        (sout,serr) = proc.communicate()
        print "  Standard output: %s" % string.rstrip(sout)
        print "  Standard error:  %s" % serr
        if (proc.returncode != 0):
            raise SlewError(star.name,"Slew error")
        elapsed = time.time()
        log.addslew(time.time()-tic)
        print "  Done: %5.1fs elapsed" % (time.time()-tic)
        if dither:
            time.sleep(1)
            for dir in directions:
                print "  Dithering %s" % dir
                tic = time.time()
                proc = subprocess.Popen(["mount",protocol,safety,"--noverbose","--host","localhost","dither","45",dir], stdout=subprocess.PIPE)
                (sout,serr) = proc.communicate()
                print "    Standard output: %s" % string.rstrip(sout)
                print "    Standard error:  %s" % serr
                if (proc.returncode != 0):
                    raise DitherError(star.name,"Dither error")
                print "    Done: %5.1fs elapsed" % (time.time()-tic)
                log.adddither(time.time()-tic)
                time.sleep(1)
        if guide:
            print "Searching for guide star"
            tic = time.time()
            proc = subprocess.Popen(["guider","magic"], stdout=subprocess.PIPE)
            (sout,serr) = proc.communicate()
            print "  Standard output: %s" % string.rstrip(sout)
            print "  Standard error:  %s" % serr
            if (proc.returncode != 0):
                raise GuideError(star.name,"Guide error (magic failed)")
            print "  Guiding for %d s" % guide_time
            time.sleep(guide_time);
            print "Attempting to stop autoguider"
            proc = subprocess.Popen(["guider","stop"], stdout=subprocess.PIPE)
            (sout,serr) = proc.communicate()
            print "  Standard output: %s" % string.rstrip(sout)
            print "  Standard error:  %s" % serr
            if (proc.returncode != 0):
                raise GuideError(star.name,"Guide error (failed to stop)")
            print "Attempting to email log"
            proc = subprocess.Popen(["email_guider_plots"], stdout=subprocess.PIPE)
            (sout,serr) = proc.communicate()
            print "  Standard output: %s" % string.rstrip(sout)
            print "  Standard error:  %s" % serr
            if (proc.returncode != 0):
                raise GuideError(star.name,"Guide error (failed to send log)")
            elapsed = time.time()
            print "  Done: %5.1fs elapsed" % (time.time()-tic)
  
    except SlewError as e:
        log.addbadslew()
        log.adderrortime(time.strftime("%H:%M:%S"))
        log.addbadstar(e.name)
        print "Error slewing to %s" % e.name 
    except DitherError as e:
        log.addbaddither()
        log.adderrortime(time.strftime("%H:%M:%S"))
        log.addbadstar(e.name)
        print "Error dithering around %s" % e.name 
    except GuideError:
        log.addbadguide()
        print "Error guiding on the target"
    except:
        print "Unrecoverable error."
        exit(1)
    finally:
        print "Slew complete"

def altitude_compare(x, y):
    if x.alt>y.alt:
       return 1
    elif x.alt==y.alt:
       return 0
    else: # x<y
       return -1

def azimuth_compare(x, y):
    if x.az>y.az:
       return 1
    elif x.az==y.az:
       return 0
    else: # x<y
       return -1

def print_stars(starList,header=False):
	if (header==True):
		print "Name            Mag       Altitude        Azimuth"
		print "--------------  ---      ----------     -----------"
	for s in starList:
		print "%-13s  %4.1f %15s %15s" % (s.name,s.mag,s.alt,s.az)	   

# The error handler sets the exit_now global variable
exit_now = False
def ctrl_c_handler(signal, frame):
        global exit_now
        exit_now = True

signal.signal(signal.SIGINT, ctrl_c_handler)


# Parse command-line options
parser = argparse.ArgumentParser(description='Exercise the telescope mount')
parser.add_argument("-v","--verbosity",help="increase output verbosity",action="store_true")
parser.add_argument("-g","--guide",help="try to autoguide",action="store_true")
parser.add_argument("-d","--dither",help="try to dither",action="store_true")
parser.add_argument("-m","--maestro",help="use keyboard maestro actions",action="store_true")
parser.add_argument("-s","--safety",help="use maestro as a backup if socket is blocked",action="store_true")
parser.add_argument("-l","--location",default="NewMexicoSkies",help="Geographical location (Toronto or NewMexicoSkies)",type=str)
args = parser.parse_args()

# Set location
if args.location == 'NewMexicoSkies' :
	myLocation = ephem.Observer()
	myLocation.lon = '-105:32.0'
	myLocation.lat = '32:54.0'
	myLocation.elevation = 2000
else: 
	if args.location == 'Toronto' :
		myLocation = ephem.city(args.location)
		myLocation.lon = '-105:32.0'
		myLocation.lat = '32:54.0'
		myLocation.elevation = 2000
	else:
		sys.exit("Unknown location.");

# Range of acceptable alt and az for stars
minAltitude = 40.
maxAltitude = 85.

# Read a list of the known bright star names
f = open('/Users/dragonfly/Dropbox/src/catalog/stars.txt','r')
lines = f.readlines()
starNames = [n.rstrip() for n in lines]

# Create a list with Star objects
stars = [ephem.star(s) for s in starNames]

# Create a list of altitudes and azimuths. I want these to be stored as
# floats rather than as ephem.Angle types, so I add 0.0 to them. They
# are in units of radians.
alt = []
az = []
for s in stars:
	s.compute(myLocation)
	alt.append(s.alt + 0.0)
	az.append(s.az + 0.0)

# Create a new list of stars at least minAltitude degrees above the horizon but
# less than maxAltitude degrees above the horizon. Sort this list by azimuth.
goodStars = [s for s in stars if (s.alt > minAltitude*math.pi/180. and s.alt < maxAltitude*math.pi/180.)]

# Slew to all of these stars (randomly)
random.shuffle(goodStars)
print_stars(goodStars,header=True)
log = Log()
[SlewScope(s,log,myLocation,args.dither,args.guide,args.maestro,args.safety) for s in goodStars]
print 'Slew times: [' + ', '.join('%.1f' % v for v in log.slewtimes) + ']'
print "Number of slew errors:   %d" % log.nbadslew
print "Maximum slew time: %.1f" % max(log.slewtimes)
if (args.dither):
    print 'Dither times: [' + ', '.join('%.1f' % v for v in log.dithertimes) + ']'
    print "Maximum dither time: %.1f" % max(log.dithertimes)
    print "Number of dither errors: %d" % log.nbaddither
if (args.guide):
    print "Number of guide errors: %d" % log.nbadguide
print 'Bad stars: [' + ', '.join('%s' % v for v in log.badstars) + ']'
print 'Error times: [' + ', '.join('%s' % v for v in log.errortimes) + ']'

# Stop mount at end of exercise
print "Stopping tracking."
maestro_string = "--nomaestro"
if (args.maestro):
    maestro_string = "--maestro"
proc = subprocess.Popen(["mount",maestro_string,"--noverbose","--host","localhost","stop"], stdout=subprocess.PIPE)
(sout,serr) = proc.communicate()
print "  Standard output: %s" % string.rstrip(sout)
print "  Standard error:  %s" % serr
if (proc.returncode != 0):
	sys.exit("Error stopping mount tracking")

