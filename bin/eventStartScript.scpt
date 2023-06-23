#!/usr/bin/env osascript

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
    -- Truncate meeting notes to first 500 characters
    if length of meetingNotes > 500 then
        set meetingNotes to text 1 thru 500 of meetingNotes
    end if

    -- Format the date and time
    set startTime to (time string of startDate) & " - " & (time string of endDate)

    -- Format the dialog message
    set dialogMessage to title & "
" & startTime & "

" & meetingService & "

" & "Notes:" & "
" & meetingNotes
    
    tell application "Finder"
        activate
        try
            with timeout of 600 seconds
                set dialogResult to display dialog dialogMessage with title "MeetingBar Auto Join" buttons {"OK", "Cancel"} default button "OK"
                
                if button returned of dialogResult is "OK" then
                    tell application "System Events"
                        open location meetingUrl
                    end tell
                end if
            end timeout
        on error number -128
            -- Do nothing when the user cancels
        end try
    end tell
end meetingStart