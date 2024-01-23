on run argv
    set eventId to item 1 of argv
    set title to item 2 of argv
    set allday to item 3 of argv
    set startDate to item 4 of argv
    set endDate to item 5 of argv
    set eventLocation to item 6 of argv
    set repeatingEvent to item 7 of argv
    set attendeeCount to item 8 of argv
    set meetingUrl to item 9 of argv
    set meetingService to item 10 of argv
    set meetingNotes to item 11 of argv


    -- If the title has "Focus Time" or "Lunch" in it, do nothing
    if title contains "Focus Time (via Clockwise)" or title contains "Lunch (via Clockwise)" then
        return
    end if
  
    -- Truncate meeting notes to first 500 characters
    if length of meetingNotes > 500 then
        set meetingNotes to text 1 thru 500 of meetingNotes
    end if

    -- Format the date and time
    set startDateAsDate to date startDate
    set endDateAsDate to date endDate
    set startTime to (time string of startDateAsDate) & " - " & (time string of endDateAsDate)

    -- Format the dialog message
    set dialogMessage to title & "
" & startTime & "

" & meetingService & "

" & "Notes:" & "
" & meetingNotes
    tell application "iTerm"
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
        on error errMsg number errNum
            do shell script "echo \"Apple  Script Error: \" & errMsg & \" Error Number: \" & errNum"
        end try
    end tell
end run
