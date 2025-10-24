#!/bin/zsh
set -e

# Define your shell variables
eventId=$(echo $1 | tr -d '"')
title=$(echo $2 | tr -dc 'a-zA-Z0-9.? ~\n' | tr -d '"')
allday=$(echo $3 | tr -d '"')
startDate=$(echo $4 | tr -d '"')
endDate=$(echo $5 | tr -d '"')
eventLocation=$(echo $6 | tr -dc 'a-zA-Z0-9.? \n' | tr -d '"')
repeatingEvent=$(echo $7 | tr -d '"')
attendeeCount=$(echo $8 | tr -d '"')
meetingUrl=$(echo $9 | tr -d '"')
meetingService=$(echo ${10} | tr -dc 'a-zA-Z0-9.? \n' | tr -d '"')

# Strip HTML tags from meeting notes
meetingNotes="${11}"
originalMeetingNotes=$meetingNotes
meetingNotes=$(echo $meetingNotes | textutil -convert txt -format html -stdin -stdout)
meetingNotes=$(echo ${meetingNotes} | tr -dc 'a-zA-Z0-9.? ~\n' | tr -d '"')

# Format event data
eventData=$(cat <<EOF

Event ID: $eventId
Title: $title
All Day: $allday
Start Date: $startDate
End Date: $endDate
Location: $eventLocation
Repeating Event: $repeatingEvent
Attendee Count: $attendeeCount
Meeting URL: $meetingUrl
Meeting Service: $meetingService
Meeting Notes: $meetingNotes
Original Meeting Notes: $originalMeetingNotes
Timestamp: $(date)

EOF
)

# Write to log file
echo "$eventData" >> ~/event-log.txt

HOME=/Users/benbernard

# Check for and invoke meeting-prompt.sh if it exists
if [ -f ~/site/meeting-prompt.sh ]; then
  echo "$(date): Calling ${HOME}/site/meeting-prompt.sh in background" >> ~/event-log.txt
  echo "SHELL: $SHELL, TERM: $TERM, DISPLAY: $DISPLAY" >> ~/event-log.txt
  echo "$eventData" | ${HOME}/site/meeting-prompt.sh --verbose &
  meeting_prompt_pid=$!
  echo "$(date): meeting-prompt.sh PID: $meeting_prompt_pid" >> ~/event-log.txt
fi

osascript ~/bin/event-prompt.applescript \
  "$eventId" \
  "$title" \
  $allday \
  "$startDate" \
  "$endDate" \
  "$eventLocation" \
  $repeatingEvent \
  $attendeeCount \
  "$meetingUrl" \
  "$meetingService" \
  "$meetingNotes" >> ~/event-log.txt 2>&1
  # "$meetingNotes"
