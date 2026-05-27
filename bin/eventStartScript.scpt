#!/usr/bin/env osascript

# Future Ben:
# This is installed by going to
# ~/Library/Application Scripts/leits.MeetingBar
# And creating a symlink to ~/bin/eventStartScript.scpt
#
# This script is the bridge between MeetingBar and the meeting-notify binary.
# Instead of passing 11 positional shell arguments (which breaks on quotes,
# newlines, or spaces in event titles), we create a temporary plist file
# with structured key-value pairs, then pass just the plist path.
#
# The meeting-notify binary reads the plist via `plutil -convert json`,
# which handles all escaping automatically. The temp file is deleted by the
# binary after reading.

-- Helper: add a string field to a plist
on addField(plistRef, fieldName, fieldValue)
    tell application "System Events"
        tell property list items of plistRef
            make new property list item at end with properties {kind:string, name:fieldName, value:fieldValue}
        end tell
    end tell
end addField

on meetingStart(eventId, title, allday, startDate, endDate, eventLocation, repeatingEvent, attendeeCount, meetingUrl, meetingService, meetingNotes)
    -- Create a temporary plist file with the event data
    set plistPath to "/tmp/meetingbar-event-" & (do shell script "date +%s%N") & ".plist"

    tell application "System Events"
        set thePlist to make new property list file with properties {name:plistPath}
    end tell

    -- Add all event fields to the plist
    addField(thePlist, "eventId", eventId as text)
    addField(thePlist, "title", title as text)
    addField(thePlist, "allday", allday as text)
    addField(thePlist, "startDate", startDate as text)
    addField(thePlist, "endDate", endDate as text)
    addField(thePlist, "eventLocation", eventLocation as text)
    addField(thePlist, "repeatingEvent", repeatingEvent as text)
    addField(thePlist, "attendeeCount", attendeeCount as text)
    addField(thePlist, "meetingUrl", meetingUrl as text)
    addField(thePlist, "meetingService", meetingService as text)
    addField(thePlist, "meetingNotes", meetingNotes as text)

    -- Call the compiled meeting-notify binary with the plist path.
    -- nohup + & backgrounds it so MeetingBar's event loop isn't blocked.
    set command to "nohup ~/bin/ts/bin/meeting-notify " & quoted form of plistPath & " > /dev/null 2>&1 &"

    -- Execute the command
    do shell script command
end meetingStart
