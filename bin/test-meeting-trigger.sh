#!/bin/zsh

# This script replicates exactly how MeetingBar triggers event-prompt.sh
# It simulates the full chain: MeetingBar -> eventStartScript.scpt -> event-prompt.sh

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  echo "Usage: $0 [EVENT_ID] [TITLE] [ALLDAY] [START_DATE] [END_DATE] [LOCATION] [REPEATING] [ATTENDEE_COUNT] [MEETING_URL] [MEETING_SERVICE] [NOTES]"
  echo ""
  echo "Example with default test values:"
  echo "  $0"
  echo ""
  echo "Example with custom values:"
  echo "  $0 'TEST-123' 'Test Meeting' false 'Thursday, October 23, 2025 at 2:00:00 PM' 'Thursday, October 23, 2025 at 2:30:00 PM' 'EMPTY' false 3 'https://meet.google.com/test' 'Google Meet' 'Test meeting notes'"
  exit 0
fi

# Use provided arguments or defaults
EVENT_ID="${1:-TEST-$(date +%s)}"
TITLE="${2:-Test Meeting $(date +%H:%M)}"
ALLDAY="${3:-false}"
START_DATE="${4:-$(date -v +5M '+%A, %B %d, %Y at %I:%M:%S %p')}"
END_DATE="${5:-$(date -v +35M '+%A, %B %d, %Y at %I:%M:%S %p')}"
LOCATION="${6:-EMPTY}"
REPEATING="${7:-false}"
ATTENDEE_COUNT="${8:-2}"
MEETING_URL="${9:-https://meet.google.com/test-abc-def}"
MEETING_SERVICE="${10:-Google Meet}"
NOTES="${11:-This is a test meeting triggered manually}"

echo "=== Simulating MeetingBar Event Trigger ==="
echo "Event ID: $EVENT_ID"
echo "Title: $TITLE"
echo "Start: $START_DATE"
echo "End: $END_DATE"
echo ""
echo "Calling event-prompt.sh in background (like MeetingBar does)..."
echo ""

# This is exactly how eventStartScript.scpt calls event-prompt.sh
nohup ~/bin/event-prompt.sh "$EVENT_ID" "$TITLE" "$ALLDAY" "$START_DATE" "$END_DATE" "$LOCATION" "$REPEATING" "$ATTENDEE_COUNT" "$MEETING_URL" "$MEETING_SERVICE" "$NOTES" > /dev/null 2>&1 &

PID=$!
echo "Background process started with PID: $PID"
echo ""
echo "Check logs:"
echo "  Event log: tail -f ~/event-log.txt"
echo "  Meeting prompt log: tail -f ~/meeting-prompt.log"
