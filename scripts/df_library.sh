#!/bin/sh

df_sleep_until_twilight () 
{

  sleep_sec=$(revised_sunset | grep SecondsUntilEveningFlats | awk '{print $2}')

  if [ $sleep_sec -gt "0" ]; then
      start_message=$(revised_sunset | grep StartEveningFlats | awk '{print "Sleeping until",$2,$3,$4,$5,$6," (MST)"}')
      echo $start_message
      sleep $sleep_sec
      echo Time for evening flats has arrived.
  else
      echo "Evening twilight is over. Proceeding without sleeping."
  fi

}

df_restart_theskyx ()
{
    osascript -e 'tell application "Keyboard Maestro Engine" to do script "Restart TheSkyX Professional Edition"'
}

df_startup ()
{
    #echo "Restarting TheSkyX"
    #restart_theskyx
    almanac > /var/tmp/almanac.txt
    mutt -s "Dragonfly activating for the night" projectdragonfly@icloud.com < /var/tmp/almanac.txt
    echo "Power up mount and guider"
    power mount on
    power guider on
    echo "Homing mount"
    mount home
    echo "Mount tracking at sidereal rate"
    echo "Powering up cameras and focusers"
    power 12V on
    sleep 5
    echo "Regulating CCDs"
    all_regulate -12
    all_regulate -12  # Paranoid
    # Check if focuser monitor is running
    isup=`ps -ae | grep focuser_monitor | grep -v grep`
    if [[ $isup ]];
    then
        echo "Focuser monitor is running."
    else
        echo Starting focuser monitor
        focuser_monitor  &
    fi
    sleep 1
    echo "Initializing focusers"
    all_initfocus
    echo "Clearing focus run completed file"
    rm -f FOCUS_RUN_COMPLETED.txt
    echo "Clearing focus now file"
    rm -f FOCUS_NOW.txt
    echo "Clearing immediate sync file"
    rm -f SYNC_NOW.txt
    echo "Clearing interrupt file"
    rm -f INTERRUPT.txt
    echo "Clearing pause file"
    rm -f PAUSE.txt
    echo "Clearing guider file"
    rm -f DO_NOT_GUIDE.txt
}

df_shutdown ()
{
    echo "Powering off cameras and focusers"
    power 12V off
    echo "Powering off guider"
    power guider off
    echo "Clearing focus file"
    rm -f FOCUS_RUN_COMPLETED.txt
    echo "Parking mount"
    mount park
    echo "Emailing weather plots"
    email_weather
    echo "Shutdown complete"
}

df_show_log ()
{
    syslog -k Message Req TheSkyX -k Time ge -12h -o -k Message Req Dragonfly -k Time ge -12h | grep -v 'Authentication: SUCCEEDED'
}

function df_bailout () {
    df_send cameras "abort"
    exit 1
}

