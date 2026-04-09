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
meetingNotesPlain=$(printf "%s" "$meetingNotes" | textutil -convert txt -format html -stdin -stdout)
meetingNotesForSummary=$(printf "%s" "$meetingNotesPlain" | perl -0pe 's/[^[:alnum:][:space:].,?!:;()&\/+-]//g; s/\s+/ /g; s/^ //; s/ $//')
meetingNotes=$(printf "%s" "$meetingNotesPlain" | tr -dc 'a-zA-Z0-9.? ~\n' | tr -d '"')

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
Meeting Notes Summary Input: $meetingNotesForSummary
Original Meeting Notes: $originalMeetingNotes
Timestamp: $(date)

EOF
)

# Write to log file
echo "$eventData" >> ~/event-log.txt

HOME=/Users/benbernard
AI_CLI="${HOME}/.config/gohan/bin/ai"
NOTIFYCTL="${HOME}/bin/ts/bin/notifyctl"
NOTIFICATION_SUMMARY_MODEL="claude-haiku-4-5"

format_notification_time() {
  local raw="$1"
  local formatted

  formatted=$(printf "%s" "$raw" | LC_ALL=C perl -0ne '
    if (/([0-9]{1,2}):([0-9]{2})(?::[0-9]{2})?[^[:alnum:]]*([AP]M)\b/i) {
      printf "%d:%s %s", $1, $2, uc($3);
    } elsif (/\b([01]?[0-9]|2[0-3]):([0-9]{2})(?::[0-9]{2})?\b/) {
      my ($hour, $minute) = ($1 + 0, $2);
      my $suffix = $hour >= 12 ? "PM" : "AM";
      $hour %= 12;
      $hour = 12 if $hour == 0;
      printf "%d:%s %s", $hour, $minute, $suffix;
    }
  ')

  formatted=$(printf "%s" "$formatted" | perl -0pe 's/\s+/ /g; s/^ //; s/ $//')
  echo "$formatted"
}

truncate_text() {
  local text="$1"
  local limit="$2"

  if (( ${#text} > limit )); then
    echo "${text[1,limit]}..."
  else
    echo "$text"
  fi
}

normalize_text() {
  printf "%s" "$1" | perl -0pe 's/\s+/ /g; s/^ //; s/ $//'
}

extract_single_sentence() {
  local text="$1"

  text=$(normalize_text "$text")
  if [ -z "$text" ]; then
    echo ""
    return 0
  fi

  printf "%s" "$text" | perl -0ne 'if (/^(.+?[.!?])(?:\s|$)/) { print $1 } else { print $_ }'
}

sanitize_notification_message() {
  local text="$1"

  text=$(normalize_text "$text")
  text=$(printf "%s" "$text" | perl -0pe 's/^[\"\x27]+//; s/[\"\x27]+$//')
  text=$(extract_single_sentence "$text")
  text=$(truncate_text "$text" 160)
  echo "$text"
}

notification_message_is_opt_out() {
  local text="$1"
  local lowered

  text=$(normalize_text "$text")
  text=$(printf "%s" "$text" | perl -0pe 's/^[\"\x27[:space:]]+//; s/[\"\x27[:space:][:punct:]]+$//')
  lowered=$(printf "%s" "$text" | tr '[:upper:]' '[:lower:]')

  [[ -z "$lowered" ||
    "$lowered" == "none" ||
    "$lowered" == "no description" ||
    "$lowered" == "no summary" ||
    "$lowered" == i\ don\'t\ have\ enough\ concrete\ detail* ||
    "$lowered" == i\ do\ not\ have\ enough\ concrete\ detail* ||
    "$lowered" == there\ is\ not\ enough\ concrete\ detail* ||
    "$lowered" == there\ are\ not\ enough\ details* ||
    "$lowered" == this\ meeting\ does\ not\ contain\ enough\ concrete\ detail* ||
    "$lowered" == not\ enough\ concrete\ detail* ||
    "$lowered" == not\ enough\ detail* ||
    "$lowered" == not\ enough\ information* ||
    "$lowered" == insufficient\ detail* ||
    "$lowered" == unable\ to\ generate* ||
    "$lowered" == cannot\ generate* ||
    "$lowered" == can\'t\ generate* ]]
}

looks_like_join_boilerplate() {
  local lowered

  lowered=$(printf "%s" "$1" | tr '[:upper:]' '[:lower:]')
  [[ "$lowered" == join\ * ||
    "$lowered" == clockwise\ may\ automatically\ move\ this\ meeting* ||
    "$lowered" == learn\ more\ about\ meet* ||
    "$lowered" == please\ do\ not\ edit\ this\ section* ||
    "$lowered" == *"meeting id"* ||
    "$lowered" == *"passcode"* ||
    "$lowered" == *"dial by"* ||
    "$lowered" == *"one tap mobile"* ||
    "$lowered" == *"least disruptive time for attendees"* ||
    "$lowered" == *"open in clockwise"* ||
    "$lowered" == *"please do not edit this section"* ||
    "$lowered" == *"google meet"* ||
    "$lowered" == *"zoom meeting"* ]]
}

generate_llm_notification_message() {
  local meeting_title="$1"
  local meeting_service="$2"
  local meeting_location="$3"
  local notes="$4"
  local prompt
  local summary
  local ai_bin=""

  if [ -z "$notes" ] || [ "$notes" = "EMPTY" ]; then
    echo ""
    return 0
  fi

  if [ -x "$AI_CLI" ]; then
    ai_bin="$AI_CLI"
  elif command -v ai >/dev/null 2>&1; then
    ai_bin="$(command -v ai)"
  else
    echo ""
    return 0
  fi

  prompt=$(cat <<EOF
Title: $meeting_title
Service: $meeting_service
Location: $meeting_location
Notes: $notes
EOF
)

  summary=$("$ai_bin" playground \
    --model "$NOTIFICATION_SUMMARY_MODEL" \
    -m "system=Write one short sentence for the body of a meeting reminder notification. Use only the provided details. Keep it to 6 to 18 words. Do not include times, links, or meeting platform names. Do not repeat the title verbatim unless necessary. If the details are mostly join instructions, boilerplate, or otherwise too thin for a useful sentence, return exactly NONE. Return only the sentence text or NONE. Never explain your choice." \
    -m "user=$prompt" \
    2>/dev/null) || {
    echo ""
    return 0
  }

  summary=$(sanitize_notification_message "$summary")
  if notification_message_is_opt_out "$summary"; then
    echo ""
    return 0
  fi

  echo "$summary"
}

generate_fallback_notification_message() {
  local notes="$1"
  local summary

  if [ -z "$notes" ] || [ "$notes" = "EMPTY" ]; then
    echo ""
    return 0
  fi

  summary=$(sanitize_notification_message "$notes")
  if [ -z "$summary" ]; then
    echo ""
    return 0
  fi

  if looks_like_join_boilerplate "$summary"; then
    echo ""
    return 0
  fi

  echo "$summary"
}

notificationMessageSource="none"

build_notification_message() {
  local meeting_title="$1"
  local meeting_service="$2"
  local meeting_location="$3"
  local notes="$4"
  local target_url="$5"

  notificationMessage=""
  notificationMessageSource="none"

  if [ "$notes" != "EMPTY" ] && [ -n "$notes" ]; then
    notificationMessage=$(generate_llm_notification_message "$meeting_title" "$meeting_service" "$meeting_location" "$notes")
    if [ -n "$notificationMessage" ]; then
      notificationMessageSource="llm"
      return 0
    fi

    notificationMessage=$(generate_fallback_notification_message "$notes")
    if [ -n "$notificationMessage" ]; then
      notificationMessageSource="fallback"
      return 0
    fi
  fi

  if [ -z "$notificationMessage" ]; then
    notificationMessage="Meeting starting now"
    notificationMessageSource="default"
  fi
}

normalize_notification_target_url() {
  local raw="$1"

  if [ "$raw" = "EMPTY" ] || [ -z "$raw" ]; then
    echo ""
    return 0
  fi

  if [[ "$raw" == gmeet://* ]]; then
    echo "$raw"
    return 0
  fi

  if [[ "$raw" == https://meet.google.com/* ]]; then
    echo "${raw/https:\/\//gmeet://}"
    return 0
  fi

  if [[ "$raw" == http://meet.google.com/* ]]; then
    echo "${raw/http:\/\//gmeet://}"
    return 0
  fi

  echo "$raw"
}

# Check for and invoke meeting-prompt.sh if it exists
if [ -f ~/site/meeting-prompt.sh ]; then
  echo "$(date): Calling ${HOME}/site/meeting-prompt.sh in background" >> ~/event-log.txt
  echo "SHELL: $SHELL, TERM: $TERM, DISPLAY: $DISPLAY" >> ~/event-log.txt
  echo "$eventData" | ${HOME}/site/meeting-prompt.sh --verbose &
  meeting_prompt_pid=$!
  echo "$(date): meeting-prompt.sh PID: $meeting_prompt_pid" >> ~/event-log.txt
fi

# Preserve the old AppleScript behavior for calendar holds that should stay silent.
if [[ "$title" == *"Focus Time (via Clockwise)"* || "$title" == *"Lunch (via Clockwise)"* ]]; then
  echo "$(date): Skipping meeting notification for title: $title" >> ~/event-log.txt
  exit 0
fi

notificationTitle="$title"
if [ -z "$notificationTitle" ]; then
  notificationTitle="Meeting starting now"
fi

startTime=$(format_notification_time "$startDate")
endTime=$(format_notification_time "$endDate")
notificationSubtitle=""
if [ -n "$startTime" ] && [ -n "$endTime" ]; then
  notificationSubtitle="$startTime-$endTime"
elif [ -n "$startTime" ]; then
  notificationSubtitle="$startTime"
elif [ -n "$endTime" ]; then
  notificationSubtitle="$endTime"
fi

notificationTargetUrl=$(normalize_notification_target_url "$meetingUrl")
build_notification_message "$notificationTitle" "$meetingService" "$eventLocation" "$meetingNotesForSummary" "$notificationTargetUrl"

if [ -x "$NOTIFYCTL" ]; then
  notificationArgs=(
    send
    meety
    --title "$notificationTitle"
    --subtitle "$notificationSubtitle"
    --message "$notificationMessage"
    --notification-id "meetingbar-${eventId}"
  )

  if [ -n "$notificationTargetUrl" ]; then
    notificationArgs+=(--data "meet_url=$notificationTargetUrl")
  else
    notificationArgs+=(--no-default-action --no-actions)
  fi

  echo "$(date): Sending native meeting notification via notifyctl" >> ~/event-log.txt
  echo "$(date): Notification subtitle: ${notificationSubtitle:-"(empty)"}" >> ~/event-log.txt
  echo "$(date): Notification target URL: ${notificationTargetUrl:-"(none)"}" >> ~/event-log.txt
  echo "$(date): Notification message source: ${notificationMessageSource}" >> ~/event-log.txt
  echo "$(date): Notification message: ${notificationMessage:-"(empty)"}" >> ~/event-log.txt
  if "$NOTIFYCTL" "${notificationArgs[@]}" >> ~/event-log.txt 2>&1; then
    exit 0
  fi

  echo "$(date): notifyctl failed, falling back to AppleScript dialog" >> ~/event-log.txt
else
  echo "$(date): notifyctl unavailable, falling back to AppleScript dialog" >> ~/event-log.txt
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
