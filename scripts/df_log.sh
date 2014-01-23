#!/bin/sh

syslog -k Message Req TheSkyX -k Time ge -12h -o -k Message Req Dragonfly -k Time ge -12h | grep -v Notice
