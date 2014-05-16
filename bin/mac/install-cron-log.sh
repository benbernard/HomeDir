#!/bin/sh

echo "cron.* /var/log/cron.log" >> /etc/syslog.conf
sudo launchctl unload /System/Library/LaunchDaemons/com.apple.syslogd.plist
sudo launchctl load /System/Library/LaunchDaemons/com.apple.syslogd.plist
