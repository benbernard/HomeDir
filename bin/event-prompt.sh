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

{
  echo
  echo "Event ID: $eventId"
  echo "Title: $title"
  echo "All Day: $allday"
  echo "Start Date: $startDate"
  echo "End Date: $endDate"
  echo "Location: $eventLocation"
  echo "Repeating Event: $repeatingEvent"
  echo "Attendee Count: $attendeeCount"
  echo "Meeting URL: $meetingUrl"
  echo "Meeting Service: $meetingService"
  echo "Meeting Notes: $meetingNotes"
  echo "Original Meeting Notes: $originalMeetingNotes"
  echo "Timestamp: $(date)"
  echo
} >> ~/event-log.txt

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
