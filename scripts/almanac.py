#!/opt/local/bin/python2.7

from __future__ import division

import datetime
import dateutil
import dateutil.tz
import argparse
import math
import ephem
import subprocess
import string

class AlmanacError(Exception):
    """Base class for exceptions in this module."""
    pass

class TimeError(AlmanacError):
    """Raised when a slew generates an error.

    Attributes:
        msg -- explanation of the error
    """
    def __init__(self, msg):
        self.msg = msg


def print_almanac(targets):
    obsDateUTC = datetime.datetime.utcnow()

    NMSkies = ephem.Observer()
    NMSkies.lat = '32:53:23'
    NMSkies.long = '-105:28:41'
    NMSkies.elevation = 7300
    NMSkies.date = obsDateUTC
    NMSkies.horizon = '0'

    db_file = "/Users/dragonfly/Dropbox/ProjectDocuments/Databases/Xephem/NGC.edb"

    # Times will be listed in the local timezone even for the remote
    # location. This is a feature not a bug!
    localtimezone = datetime.datetime.now(dateutil.tz.tzlocal()).tzname()

    # Sun rise/set
    sunsetUTC = NMSkies.next_setting(ephem.Sun(),use_center=True)
    sunriseUTC = NMSkies.next_rising(ephem.Sun(),use_center=True)
    sunsetMST = ephem.localtime(sunsetUTC)
    sunriseMST = ephem.localtime(sunriseUTC)

    # Sun altitude
    s = ephem.Sun()
    s.compute(NMSkies)
    sunalt = float(s.alt)*180/math.pi

    # Sun hour angle
    lst = NMSkies.sidereal_time() 
    sun_ha = (lst - s.ra)*180/math.pi/15.0
    if sun_ha > 12:
        sun_ha = sun_ha - 24.0
    if sun_ha < -12:
        sun_ha = sun_ha + 24.0

    # Moon altitude
    m = ephem.Moon()
    m.compute(NMSkies)
    moonalt = float(m.alt)*180/math.pi

    # Moon phase
    moonphase = float(m.moon_phase)

    # Moonrise/set
    moonriseUTC = NMSkies.next_rising(ephem.Moon(),use_center=True)
    moonsetUTC = NMSkies.next_setting(ephem.Moon(),use_center=True)
    moonriseMST = ephem.localtime(moonriseUTC)
    moonsetMST = ephem.localtime(moonsetUTC)

    # Times for flats. Evening flats should start when the sun is at -5.
    # Morning flats should start when the sun is at -10 (these are guesses).
    # So just set these to be the horizons and re-compute time of sunrise and sunset.
    NMSkies.horizon = '-5'
    eveningFlatUTC = NMSkies.next_setting(ephem.Sun(),use_center=True)
    eveningFlatMST = ephem.localtime(eveningFlatUTC)
    NMSkies.horizon = '-10'
    morningFlatUTC = NMSkies.next_rising(ephem.Sun(),use_center=True)
    morningFlatMST = ephem.localtime(morningFlatUTC)

    # Time until flats in seconds
    hoursUntilEveningFlats = 24*(eveningFlatUTC - ephem.now());
    secondsUntilEveningFlats = int(3600*hoursUntilEveningFlats);

    # Work out what we should probably be doing
    if sunalt > 0:
        action = 'Park'
    elif sunalt > -12:
        if sun_ha >= 0:
            action = 'EveningFlat'
        else:
            action = 'MorningFlat'
    else:
        action = 'Observe'

    # Output suggested action to the user
    print 'Location                 ','NewMexicoSkies'
    print 'TimeZoneForListedTimes   ',localtimezone
    print 'SuggestedAction          ',action
    print 'SiderealTime             ',str(lst) 
    print 'Sunset                   ',ephem.Date(sunsetMST)
    print 'Sunrise                  ',ephem.Date(sunriseMST)
    print 'SunAltitude              %-+9.3f      [deg]' % sunalt
    print 'SunHourAngle             %-+9.3f      [hour]' % sun_ha
    print 'MoonAltitude             %-+9.3f      [deg]' % moonalt
    print 'Moonrise                 ',ephem.Date(moonriseMST)
    print 'Moonset                  ',ephem.Date(moonsetMST)
    print 'MoonPhase                 %-9.2f' % moonphase
    print 'StartEveningFlats        ',ephem.Date(eveningFlatMST)
    print 'StartMorningFlats        ',ephem.Date(morningFlatMST)
    print 'HoursUntilEveningFlats   ',hoursUntilEveningFlats;
    print 'SecondsUntilEveningFlats ',secondsUntilEveningFlats;


    if targets:
        print ''
        print 'Name          Altitude    Azimuth     HA         MoonSep     Rise       Transit    Set' 

    for name in targets:
        target_line = ""
        for db_line in open(db_file):
            if name in db_line:
                target_line = db_line
                break
        if (target_line):
            target=ephem.readdb(target_line)
            target.compute(NMSkies)
            target_alt = float(target.alt)*180/math.pi
            target_rt = target.rise_time
            target_tt = target.transit_time
            target_st = target.set_time
            target_az = float(target.az)*180/math.pi
            target_ha = (lst - target.ra)*180/math.pi/15.0
            target_moon_sep = (ephem.separation(target,m))*180/math.pi
            if target_ha > 12:
                target_ha = target_ha - 24.0
            if target_ha < -12:
                target_ha = target_ha + 24.0

            riseTimeString = str(ephem.Date(ephem.localtime(ephem.Date(target_rt)))).split(' ')[1]
            transitTimeString = str(ephem.Date(ephem.localtime(ephem.Date(target_tt)))).split(' ')[1]
            setTimeString = str(ephem.Date(ephem.localtime(ephem.Date(target_st)))).split(' ')[1]
            
            outline = "%-10s  %+9.3f   %+9.3f  %+9.3f   %+9.3f   %10s %10s %10s" % \
                      ("\'"+name+"\'", target_alt, target_az, target_ha, target_moon_sep, \
                      riseTimeString, transitTimeString, setTimeString)
            print outline

    return None

if __name__ == '__main__':

    # Parse command-line options
    parser = argparse.ArgumentParser(description='Display a nightly almanac.')
    parser.add_argument("-v","--verbosity",help="increase output verbosity",action="store_true")
    parser.add_argument('targets',nargs='*', help="targets to investigate",default = '')
    args = parser.parse_args()

    # Get targets
    targets = args.targets

    print_almanac(targets)
