#!/usr/bin/env osascript

# Future Ben:
# This is installed by going to 
# ~Library/Application Scripts/leits.MeetingBar
# And creating a symlink to ~/bin/eventStartScript.scpt

# the method to be called with the following parameters for the next meeting.
#
# 1. parameter - eventId (string) - unique identifier from apples eventkit implementation
# 2. parameter - title (string) - the title of the event (event title can be null, although it makes no sense!)
# 3. parameter - allday (bool) - true for allday events, false for non allday events
# 4. parameter - startDate (date) - needs casting in apple script to output (e.g. startDate as text)
# 5 .parameter - endDate (date) - needs casting in apple script to output (e.g. startDate as text)
# 6. parameter - eventLocation (string) - if no location is set, the value will be "EMPTY"
# 7. parameter - repeatingEvent (bool) - true if it is part of an repeating event, false for single event
# 8. parameter - attendeeCount (int32) - number of attendees- 0 for events without attendees
# 9. parameter - meetingUrl (string) - the url to the meeting found in notes, url or location - only one meeting url is supported - if no meeting url is set, the value will be "EMPTY"
# 10. parameter - meetingService (string), e.g MS Teams or Zoom- if no meeting service is found, the meeting service value is "EMPTY"
# 11. parameter - meetingNotes (string)- the complete notes of a meeting -  if no notes are set, value "EMPTY" will be used

on meetingStart(eventId, title, allday, startDate, endDate, eventLocation, repeatingEvent, attendeeCount, meetingUrl, meetingService, meetingNotes)
    -- Convert all parameters to text
    set eventId to eventId as text
    set title to title as text
    set allday to allday as text
    set startDate to startDate as text
    set endDate to endDate as text
    set eventLocation to eventLocation as text
    set repeatingEvent to repeatingEvent as text
    set attendeeCount to attendeeCount as text
    set meetingUrl to meetingUrl as text
    set meetingService to meetingService as text
    set meetingNotes to meetingNotes as text

    -- Prepare the command to call the other script with all parameters
    set command to "nohup ~/bin/event-prompt.sh " & eventId & " " & quoted form of title & " " & allday & " " & quoted form of startDate & " " & quoted form of endDate & " " & quoted form of eventLocation & " " & repeatingEvent & " " & attendeeCount & " " & quoted form of meetingUrl & " " & quoted form of meetingService & " " & quoted form of meetingNotes & " > /dev/null 2>&1 &"

    -- Execute the command
    do shell script command
end meetingStart
