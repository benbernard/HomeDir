#!/bin/zsh

# This script replicates exactly how MeetingBar triggers event-prompt.sh
# It simulates the full chain: MeetingBar -> eventStartScript.scpt -> event-prompt.sh
#
# DEFAULT: dry-run (no overlay popup). Use --live to actually show the overlay.

LIVE=false

# Handle flags before positional args
  while [[ "$1" == --* ]]; do
  case "$1" in
    --live) LIVE=true; shift ;;
    --dry-run) shift ;; # default anyway, just consume it
    --help|-h)
      cat <<'HELP'
Usage: test-meeting-trigger.sh [OPTIONS] [ARGS...]

Options:
  --live          Actually show the overlay (default is dry-run)
  --dry-run       Explicitly request dry-run (same as default)
  -h, --help      Show this help

Positional args (optional):
  EVENT_ID TITLE ALLDAY START_DATE END_DATE LOCATION REPEATING ATTENDEE_COUNT MEETING_URL MEETING_SERVICE NOTES

Examples:
  # Dry-run test (no overlay popup):
  test-meeting-trigger.sh

  # Live test with overlay:
  test-meeting-trigger.sh --live

  # Custom event (dry-run):
  test-meeting-trigger.sh 'TEST-123' 'Test Meeting' false 'Thursday, May 22, 2026 at 2:00:00 PM' 'Thursday, May 22, 2026 at 2:30:00 PM' 'EMPTY' false 3 'https://meet.google.com/test' 'Google Meet' 'Test notes'
HELP
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

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

MODE="dry-run"
EXTRA_FLAGS="--dry-run"
if [[ "$LIVE" = true ]]; then
  MODE="LIVE (overlay will appear)"
  EXTRA_FLAGS=""
fi

echo "=== Simulating MeetingBar Event Trigger ==="
echo "Mode: $MODE"
echo "Event ID: $EVENT_ID"
echo "Title: $TITLE"
echo "Start: $START_DATE"
echo "End: $END_DATE"
echo ""
echo "Calling event-prompt.sh in background (like MeetingBar does)..."
echo ""

# This is exactly how eventStartScript.scpt calls event-prompt.sh
# Pass --dry-run through to meeting-prompt.sh via the event data
nohup ~/bin/event-prompt.sh $EXTRA_FLAGS "$EVENT_ID" "$TITLE" "$ALLDAY" "$START_DATE" "$END_DATE" "$LOCATION" "$REPEATING" "$ATTENDEE_COUNT" "$MEETING_URL" "$MEETING_SERVICE" "$NOTES" > /dev/null 2>&1 &

PID=$!
echo "Background process started with PID: $PID"
echo ""
echo "Check logs:"
echo "  Event log:     tail -f ~/event-log.txt"
echo "  Meeting log:   tail -f ~/meeting-prompt.log"
