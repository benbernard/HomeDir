tell application "System Events"
    set isZoomRunning to (count of (every process whose name is "zoom.us")) > 0
end tell

set foundWindow to false

if isZoomRunning then
	tell application "System Events"
		tell process "zoom.us"
			set allZoomWindows to every window
			repeat with currentWindow in allZoomWindows
				set windowName to the name of currentWindow
				if windowName is not "Zoom" and (windowName is not missing value and windowName is not "") then
					set foundWindow to true
					do shell script "open -a zoom.us"
					perform action "AXRaise" of currentWindow
					exit repeat
				end if
			end repeat
		end tell
	end tell
end if

tell application "System Events"
    try
        do shell script "open ~/Applications/Chrome\\ Apps.localized/Google\\ Meet.app"
    on error errMsg
        display dialog "Error: " & errMsg
    end try
end tell

-- if not foundWindow then
    -- Open MeetInOne
    -- tell application "MeetInOne"

    -- -- Check for Google Meet tab in Google Chrome
    -- tell application "Google Chrome"
    --     set allWindows to every window
    --     repeat with currentWindow in allWindows
    --         set allTabs to every tab in currentWindow

    --         repeat with i from 1 to length of allTabs
    --             if the URL of (item i of allTabs) contains "meet.google.com" then
    --                 set foundWindow to true
    --                 -- Raise window and switch to the Google Meet tab
    --                 activate currentWindow
    --                 tell currentWindow to set {index, active tab index} to {1, i}
    --                 exit repeat
    --             end if
    --         end repeat
    --         if foundWindow then exit repeat
    --     end repeat

    --     if not foundWindow then
    --         display alert "No window found" message "An active Zoom call or Google Meet tab was not found."
    --     end if
    -- end tell
-- end if

