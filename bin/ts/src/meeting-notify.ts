#!/usr/bin/env tsx

/**
 * meeting-notify
 *
 * Replaces event-prompt.sh and meeting-prompt.sh.
 * Receives a plist file path from MeetingBar via AppleScript,
 * reads the event data via `plutil -convert json`, then:
 *   1. Fetches other upcoming meetings from Google Calendar (via gws CLI)
 *   2. Builds meetings JSON
 *   3. Launches the Swift overlay
 *   4. Sends native macOS notification via notifyctl
 *
 * Data flow:
 *   MeetingBar -> eventStartScript.scpt (AppleScript) -> creates temp plist
 *   -> meeting-notify (this binary) -> reads plist via plutil -convert json
 *   -> fetches calendar -> launches overlay + notification
 *
 * Usage:
 *   meeting-notify [--dry-run] <plist-path>
 *
 * All-day events are excluded from the overlay since they lack specific
 * start times and are not actionable meetings.
 */

import { execFileSync, execSync, spawn } from "child_process";
// spawn is used for launching the overlay process
import { appendFileSync, existsSync, unlinkSync } from "fs";
import { homedir } from "os";
import { join } from "path";

interface EventData {
  eventId: string;
  title: string;
  allDay: string;
  startDate: string;
  endDate: string;
  location: string;
  repeating: string;
  attendeeCount: string;
  meetingUrl: string;
  meetingService: string;
  meetingNotes: string;
}

interface LogEntry {
  timestamp: string;
  level: "info" | "error" | "debug" | "warn";
  component: string;
  message: string;
  details?: Record<string, unknown>;
}

const LOG_FILE = join(homedir(), "event-log.txt");
const MEETING_PROMPT_LOG = join(homedir(), "meeting-prompt.log");
const MEETING_OVERLAY = join(homedir(), "bin", "meeting-overlay");
const NOTIFYCTL = join(homedir(), "bin", "ts", "bin", "notifyctl");
const GWS_BIN = join(homedir(), ".config", "gohan", "bin", "gws");
const UPCOMING_WINDOW_MS = 15 * 60 * 1000;
const RECENT_START_GRACE_MS = 60 * 1000;
const ACTIVE_MEETING_NOTIFICATION_ID = "meetingbar-active";

function writeLog(entry: LogEntry): void {
  const line = JSON.stringify({
    ...entry,
    _raw: `${entry.timestamp} [${entry.level.toUpperCase()}] ${
      entry.component
    }: ${entry.message}`,
  });
  appendFileSync(LOG_FILE, `${line}\n`);
}

function sanitizeString(input: string): string {
  // Remove HTML tags
  const noHtml = input.replace(/<[^>]*>/g, " ");
  // Remove non-printable characters but keep spaces, newlines
  return noHtml
    .replace(/[^\x20-\x7E\n\t]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function formatNotificationTime(raw: string): string {
  // Parse "Friday, May 22, 2026 at 4:45:00 PM" or "Friday, May 22, 2026 at 4:45:00\u202fPM"
  const cleaned = raw.replace(/\u202f/g, " ").trim();
  const match = cleaned.match(/(\d{1,2}):(\d{2})(?::\d{2})?\s*([AP]M)/i);
  if (match) {
    const [_, hour, minute, ampm] = match;
    const h = parseInt(hour, 10);
    const suffix = ampm.toUpperCase();
    const displayHour = h % 12 || 12;
    return `${displayHour}:${minute} ${suffix}`;
  }
  return cleaned;
}

function buildCalendarUrl(startDate: string): string {
  // Parse date like "Friday, May 22, 2026 at 4:45:00 PM"
  const cleaned = startDate.replace(/\u202f/g, " ");
  const match = cleaned.match(
    /([A-Za-z]+),\s+([A-Za-z]+)\s+(\d{1,2}),\s+(\d{4})/,
  );
  if (match) {
    const [_, _day, month, day, year] = match;
    const monthNum = new Date(`${month} 1, 2000`).getMonth() + 1;
    return `https://calendar.google.com/calendar/r/day/${year}/${monthNum}/${day}`;
  }
  // Fallback to today
  const now = new Date();
  return `https://calendar.google.com/calendar/r/day/${now.getFullYear()}/${
    now.getMonth() + 1
  }/${now.getDate()}`;
}

interface MeetingInfo {
  title: string;
  url: string;
  time: string;
}

/**
 * Reads a plist file created by the AppleScript bridge and converts it
 * to JSON using macOS's built-in plutil tool. This avoids all shell
 * escaping issues that would occur with passing 11 positional arguments.
 */
function readPlist(plistPath: string): EventData {
  const jsonStr = execSync(
    `plutil -convert json -o - "${plistPath}"`,
    { encoding: "utf-8", timeout: 5000 },
  );
  const data = JSON.parse(jsonStr) as Record<string, string>;

  return {
    eventId: data.eventId || "",
    title: sanitizeString(data.title || ""),
    allDay: data.allday || "false",
    startDate: sanitizeString(data.startDate || ""),
    endDate: sanitizeString(data.endDate || ""),
    location: sanitizeString(data.eventLocation || "EMPTY"),
    repeating: data.repeatingEvent || "false",
    attendeeCount: data.attendeeCount || "0",
    meetingUrl: sanitizeString(data.meetingUrl || "EMPTY"),
    meetingService: sanitizeString(data.meetingService || "EMPTY"),
    meetingNotes: sanitizeString(data.meetingNotes || "EMPTY"),
  };
}

/**
 * Fetches upcoming meetings from Google Calendar via the gws CLI tool.
 * Queries the next 15 minutes of events and filters out all-day events
 * (which have start.date but no start.dateTime, e.g. "Home" location events).
 */
function fetchCalendarEvents(): MeetingInfo[] {
  if (!existsSync(GWS_BIN)) {
    return [];
  }

  try {
    const now = new Date();
    const later = new Date(now.getTime() + UPCOMING_WINDOW_MS);

    const timeMin = now.toISOString();
    const timeMax = later.toISOString();

    const params = JSON.stringify({
      calendarId: "ben.bernard@instacart.com",
      timeMin,
      timeMax,
      singleEvents: true,
      orderBy: "startTime",
    });

    const result = execSync(
      `${GWS_BIN} calendar events list --params '${params}'`,
      { encoding: "utf-8", timeout: 10000, stdio: ["pipe", "pipe", "pipe"] },
    );

    // gws outputs a log line first ("Using keyring backend: ..."), then pretty-printed JSON
    const lines = result.split("\n");
    // Find the first line that looks like JSON start
    const jsonStartIndex = lines.findIndex(
      (line) => line.trim().startsWith("{") || line.trim().startsWith("["),
    );
    if (jsonStartIndex === -1) {
      writeLog({
        timestamp: new Date().toISOString(),
        level: "warn",
        component: "calendar",
        message: "No JSON found in gws output",
        details: { lines: lines.slice(0, 5) },
      });
      return [];
    }

    // Collect all lines from JSON start to end
    const jsonString = lines.slice(jsonStartIndex).join("\n");
    const data = JSON.parse(jsonString);
    const events = data.items || [];

    return events
      .filter((ev: Record<string, unknown>) => {
        const start = (ev.start as Record<string, string>) || {};
        // All-day events only have start.date (no start.dateTime).
        // These are not actionable meetings (e.g. "Home", "Out of office").
        return !!start.dateTime && eventStartsSoon(start.dateTime, now, later);
      })
      .map((ev: Record<string, unknown>) => {
        const start = (ev.start as Record<string, string>) || {};
        const startTime = start.dateTime || "";

        // Extract URL
        let url = "";
        const hangoutLink = ev.hangoutLink as string;
        if (hangoutLink) {
          url = hangoutLink;
        } else {
          const conferenceData =
            (ev.conferenceData as Record<string, unknown>) || {};
          const entryPoints =
            (conferenceData.entryPoints as Array<Record<string, string>>) || [];
          const videoEntry = entryPoints.find(
            (ep) => ep.entryPointType === "video",
          );
          if (videoEntry) {
            url = videoEntry.uri || "";
          }
        }

        if (!url) {
          const loc = (ev.location as string) || "";
          if (loc.includes("meet.google") || loc.includes("zoom.us")) {
            url = loc;
          }
        }

        return {
          title: (ev.summary as string) || "(No title)",
          url,
          time: startTime,
        };
      });
  } catch (error) {
    writeLog({
      timestamp: new Date().toISOString(),
      level: "error",
      component: "calendar",
      message: "Failed to fetch calendar events",
      details: { error: String(error) },
    });
    return [];
  }
}

function generateNotificationMessage(
  title: string,
  service: string,
  notes: string,
): { message: string; source: string } {
  if (!notes || notes === "EMPTY") {
    return { message: "Meeting starting now", source: "default" };
  }

  // Check for join boilerplate
  const lower = notes.toLowerCase();
  if (
    lower.includes("meeting id") ||
    lower.includes("passcode") ||
    lower.includes("dial by") ||
    lower.includes("google meet") ||
    lower.includes("zoom meeting") ||
    lower.includes("please do not edit")
  ) {
    return { message: "Meeting starting now", source: "default" };
  }

  // Truncate and sanitize
  const clean = notes.replace(/\s+/g, " ").trim().slice(0, 160);

  if (clean.length > 0) {
    return { message: clean, source: "notes" };
  }

  return { message: "Meeting starting now", source: "default" };
}

function normalizeUrl(raw: string): string {
  if (raw === "EMPTY" || !raw) return "";
  if (raw.startsWith("gmeet://")) return raw;
  if (raw.startsWith("https://meet.google.com/")) {
    return raw.replace("https://", "gmeet://");
  }
  if (raw.startsWith("http://meet.google.com/")) {
    return raw.replace("http://", "gmeet://");
  }
  return raw;
}

function eventStartsSoon(startTime: string, now: Date, later: Date): boolean {
  const startMs = Date.parse(startTime);
  if (Number.isNaN(startMs)) {
    return false;
  }

  return (
    startMs >= now.getTime() - RECENT_START_GRACE_MS &&
    startMs <= later.getTime()
  );
}

function terminateExistingOverlay(): void {
  try {
    execFileSync("/usr/bin/pkill", ["-x", "meeting-overlay"], {
      stdio: "ignore",
    });
  } catch {
    // No existing overlay is fine.
  }
}

function parseArgs(): { plistPath: string | null; isDryRun: boolean } {
  const args = process.argv.slice(2);
  let isDryRun = false;
  let plistPath: string | null = null;

  for (const arg of args) {
    if (arg === "--dry-run") {
      isDryRun = true;
    } else if (!plistPath) {
      plistPath = arg;
    }
  }

  return { plistPath, isDryRun };
}

async function main(): Promise<void> {
  const { plistPath, isDryRun } = parseArgs();

  if (!plistPath || !existsSync(plistPath)) {
    writeLog({
      timestamp: new Date().toISOString(),
      level: "error",
      component: "main",
      message: "Missing or invalid plist path",
      details: { plistPath },
    });
    process.exit(1);
  }

  let eventData: EventData;
  try {
    eventData = readPlist(plistPath);
  } catch (error) {
    writeLog({
      timestamp: new Date().toISOString(),
      level: "error",
      component: "main",
      message: "Failed to read plist",
      details: { plistPath, error: String(error) },
    });
    process.exit(1);
  }

  // Clean up the temporary plist file
  try {
    unlinkSync(plistPath);
  } catch {
    // Ignore cleanup errors
  }

  writeLog({
    timestamp: new Date().toISOString(),
    level: "info",
    component: "main",
    message: "Received event data",
    details: { eventId: eventData.eventId, title: eventData.title },
  });

  // Skip silent events
  if (
    eventData.title.includes("Focus Time (via Clockwise)") ||
    eventData.title.includes("Lunch (via Clockwise)")
  ) {
    writeLog({
      timestamp: new Date().toISOString(),
      level: "info",
      component: "main",
      message: "Skipping silent event",
    });
    return;
  }

  // Build calendar URL
  const calUrl = buildCalendarUrl(eventData.startDate);

  // Fetch other upcoming meetings
  const otherMeetings = fetchCalendarEvents();

  // Build meetings JSON
  const triggered: MeetingInfo = {
    title: eventData.title,
    url: eventData.meetingUrl === "EMPTY" ? "" : eventData.meetingUrl,
    time: eventData.startDate,
  };

  const seen = new Set([triggered.title]);
  const meetings: MeetingInfo[] = [triggered];

  for (const m of otherMeetings) {
    if (seen.has(m.title)) continue;
    seen.add(m.title);
    meetings.push(m);
  }

  const meetingsJson = JSON.stringify(meetings);

  writeLog({
    timestamp: new Date().toISOString(),
    level: "info",
    component: "main",
    message: "Built meetings JSON",
    details: { count: meetings.length, jsonLength: meetingsJson.length },
  });

  // Launch overlay
  if (!isDryRun && existsSync(MEETING_OVERLAY)) {
    writeLog({
      timestamp: new Date().toISOString(),
      level: "info",
      component: "overlay",
      message: "Launching overlay",
    });

    try {
      terminateExistingOverlay();

      const overlayProcess = spawn(
        MEETING_OVERLAY,
        ["--meetings-json", meetingsJson, "--cal-url", calUrl],
        { detached: true, stdio: "ignore" },
      );
      overlayProcess.unref();

      writeLog({
        timestamp: new Date().toISOString(),
        level: "info",
        component: "overlay",
        message: "Overlay launched",
        details: { pid: overlayProcess.pid },
      });
    } catch (error) {
      writeLog({
        timestamp: new Date().toISOString(),
        level: "error",
        component: "overlay",
        message: "Failed to launch overlay",
        details: { error: String(error) },
      });
    }
  } else if (isDryRun) {
    writeLog({
      timestamp: new Date().toISOString(),
      level: "info",
      component: "overlay",
      message: "Dry run: skipped overlay launch",
    });
  } else {
    writeLog({
      timestamp: new Date().toISOString(),
      level: "warn",
      component: "overlay",
      message: "Overlay binary not found",
    });
  }

  // Send notification
  const startTime = formatNotificationTime(eventData.startDate);
  const endTime = formatNotificationTime(eventData.endDate);
  const subtitle =
    startTime && endTime ? `${startTime}-${endTime}` : startTime || endTime;

  const { message: notificationMessage, source } = generateNotificationMessage(
    eventData.title,
    eventData.meetingService,
    eventData.meetingNotes,
  );

  const targetUrl = normalizeUrl(eventData.meetingUrl);

  writeLog({
    timestamp: new Date().toISOString(),
    level: "info",
    component: "notification",
    message: "Sending notification",
    details: { subtitle, source, hasUrl: !!targetUrl },
  });

  if (existsSync(NOTIFYCTL)) {
    try {
      const args = [
        "send",
        "meety",
        "--title",
        eventData.title || "Meeting starting now",
        "--subtitle",
        subtitle,
        "--message",
        notificationMessage,
        "--notification-id",
        ACTIVE_MEETING_NOTIFICATION_ID,
      ];

      if (targetUrl) {
        args.push("--data", `meet_url=${targetUrl}`);
      } else {
        args.push("--no-default-action", "--no-actions");
      }

      execSync(
        `${NOTIFYCTL} ${args
          .map((a) => `"${a.replace(/"/g, '\\"')}"`)
          .join(" ")}`,
        {
          encoding: "utf-8",
        },
      );

      writeLog({
        timestamp: new Date().toISOString(),
        level: "info",
        component: "notification",
        message: "Notification sent successfully",
      });
    } catch (error) {
      writeLog({
        timestamp: new Date().toISOString(),
        level: "error",
        component: "notification",
        message: "Failed to send notification",
        details: { error: String(error) },
      });
    }
  } else {
    writeLog({
      timestamp: new Date().toISOString(),
      level: "warn",
      component: "notification",
      message: "notifyctl not found",
    });
  }

  writeLog({
    timestamp: new Date().toISOString(),
    level: "info",
    component: "main",
    message: "Processing complete",
  });
}

// Note: This binary is invoked from AppleScript with `nohup ... &`,
// so it already runs in the background. No need to fork internally.
main().catch((err) => {
  writeLog({
    timestamp: new Date().toISOString(),
    level: "error",
    component: "main",
    message: "Unhandled error",
    details: { error: String(err) },
  });
  process.exit(1);
});
