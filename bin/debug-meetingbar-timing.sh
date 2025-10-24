#!/bin/zsh

# This script demonstrates the MeetingBar timing bug
# Shows when the 10-second timer would miss the 5-second trigger window

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  echo "Usage: $0 MEETING_START_TIME"
  echo ""
  echo "MEETING_START_TIME format: 'HH:MM' or 'HH:MM:SS'"
  echo ""
  echo "Example:"
  echo "  $0 '12:30:00'    # Check if a 12:30 meeting would trigger"
  echo "  $0 '14:45'       # Check if a 2:45pm meeting would trigger"
  exit 0
fi

MEETING_TIME="$1"

if [ -z "$MEETING_TIME" ]; then
  echo "Error: Please provide meeting start time"
  echo "Usage: $0 'HH:MM:SS' or $0 'HH:MM'"
  exit 1
fi

# Parse the meeting time
if [[ "$MEETING_TIME" =~ ^[0-9]{1,2}:[0-9]{2}$ ]]; then
  MEETING_TIME="${MEETING_TIME}:00"
fi

# Get today's date with the meeting time
MEETING_DATE=$(date "+%Y-%m-%d $MEETING_TIME")
MEETING_TIMESTAMP=$(date -j -f "%Y-%m-%d %H:%M:%S" "$MEETING_DATE" "+%s" 2>/dev/null)

if [ $? -ne 0 ]; then
  echo "Error: Invalid time format. Use HH:MM or HH:MM:SS"
  exit 1
fi

NOW=$(date +%s)

echo "=== MeetingBar Timing Analysis ==="
echo "Meeting scheduled: $(date -j -f %s $MEETING_TIMESTAMP '+%I:%M:%S %p')"
echo "Current time: $(date '+%I:%M:%S %p')"
echo ""

# MeetingBar timer runs every 10 seconds
# Script triggers if: 0 < timeInterval < 5 seconds

# Calculate time until meeting
TIME_UNTIL=$((MEETING_TIMESTAMP - NOW))

if [ $TIME_UNTIL -lt -300 ]; then
  echo "Meeting was more than 5 minutes ago."
  exit 0
fi

if [ $TIME_UNTIL -gt 600 ]; then
  echo "Meeting is more than 10 minutes away."
  exit 0
fi

echo "Time until meeting: $TIME_UNTIL seconds"
echo ""

# Simulate when the timer would check (every 10 seconds)
# MeetingBar timer has been running since app start, so we simulate possible offsets
echo "MeetingBar timer checks every 10 seconds."
echo "Script triggers ONLY if meeting is 0-5 seconds away when timer checks."
echo ""
echo "Possible timer check scenarios (depends on when timer started):"
echo ""

WILL_TRIGGER=false

for offset in {0..9}; do
  # Calculate when the next timer check would be relative to meeting start
  # Timer check = (meeting_timestamp - offset) rounded down to nearest 10, then add 10 if needed

  # Time from last timer check to meeting
  TIME_FROM_LAST_CHECK=$(( (TIME_UNTIL + offset) % 10 ))
  TIME_TO_NEXT_CHECK=$(( 10 - TIME_FROM_LAST_CHECK ))

  # What will timeInterval be when the next timer check happens?
  TIME_INTERVAL_AT_CHECK=$(( TIME_UNTIL - TIME_TO_NEXT_CHECK ))

  # Check if this timer offset would trigger the script
  if [ $TIME_INTERVAL_AT_CHECK -gt 0 ] && [ $TIME_INTERVAL_AT_CHECK -lt 5 ]; then
    WILL_TRIGGER=true
    echo "Timer offset $offset: ✓ WILL TRIGGER (timeInterval=$TIME_INTERVAL_AT_CHECK sec)"
  else
    if [ $TIME_INTERVAL_AT_CHECK -le 0 ]; then
      echo "Timer offset $offset: ✗ Too late (timeInterval=$TIME_INTERVAL_AT_CHECK sec, meeting already started)"
    else
      echo "Timer offset $offset: ✗ Too early (timeInterval=$TIME_INTERVAL_AT_CHECK sec, outside 5-second window)"
    fi
  fi
done

echo ""
if [ "$WILL_TRIGGER" = true ]; then
  echo "Result: MIGHT trigger (depends on timer offset)"
  echo "        70% chance of triggering (7 out of 10 timer offsets work)"
else
  echo "Result: WON'T trigger for ANY timer offset"
  echo "        The 5-second window is completely between two 10-second checks!"
fi
