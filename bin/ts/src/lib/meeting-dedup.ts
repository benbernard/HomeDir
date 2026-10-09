export interface MeetingLike {
  title: string;
  url: string;
  time: string;
}

/**
 * Normalize a meeting URL so the same link from different sources compares
 * equal. Google Meet HTTPS links are treated as equivalent to their gmeet://
 * form, and the placeholder MeetingBar sends for "no link" becomes empty.
 */
export function normalizeMeetingUrl(raw: string): string {
  const value = (raw ?? "").trim();
  if (!value || value === "EMPTY") return "";
  if (value.startsWith("gmeet://")) return value;
  if (value.startsWith("https://meet.google.com/")) {
    return value.replace("https://", "gmeet://");
  }
  if (value.startsWith("http://meet.google.com/")) {
    return value.replace("http://", "gmeet://");
  }
  return value;
}

/**
 * Normalize a title for comparison. MeetingBar and the Google Calendar API
 * disagree on punctuation for the same event (for example "Alex Kim" vs
 * "Alex <> Kim", or a title where one side drops an em dash), so compare
 * only letters and digits.
 */
export function normalizeMeetingTitle(title: string): string {
  return (title ?? "")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
}

/**
 * Normalize a meeting start time so the two sources compare equal.
 *
 * MeetingBar sends a localized string such as
 * "Thursday, October 8, 2026 at 4:00:00 PM" while the Google Calendar API
 * sends RFC3339 such as "2026-10-08T16:00:00-07:00". Both are reduced to a
 * local wall-clock key (minute precision). Unparseable input is returned
 * trimmed so identical strings still compare equal and different strings do
 * not.
 */
export function normalizeMeetingTime(raw: string): string {
  const value = (raw ?? "").replace(/\u202f/g, " ").trim();
  if (!value) return "";

  // MeetingBar format: "Thursday, October 8, 2026 at 4:00:00 PM"
  const bar = value.match(
    /^[A-Za-z]+,\s+([A-Za-z]+)\s+(\d{1,2}),\s+(\d{4})\s+at\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AP]M)$/i,
  );
  if (bar) {
    const [, monthName, day, year, hour, minute, , meridiem] = bar;
    const month = new Date(`${monthName} 1, 2000`).getMonth();
    if (!Number.isNaN(month)) {
      const hour24 =
        (parseInt(hour, 10) % 12) + (meridiem.toUpperCase() === "PM" ? 12 : 0);
      const pad = (n: number) => String(n).padStart(2, "0");
      return `${year}-${pad(month + 1)}-${day.padStart(2, "0")} ${pad(
        hour24,
      )}:${minute}`;
    }
  }

  // RFC3339 / ISO8601: "2026-10-08T16:00:00-07:00"
  const parsed = new Date(value);
  if (!Number.isNaN(parsed.getTime())) {
    const pad = (n: number) => String(n).padStart(2, "0");
    return `${parsed.getFullYear()}-${pad(parsed.getMonth() + 1)}-${pad(
      parsed.getDate(),
    )} ${pad(parsed.getHours())}:${pad(parsed.getMinutes())}`;
  }

  return value;
}

/**
 * Whether two meetings refer to the same event.
 *
 * Two non-empty URLs that match are authoritative. Otherwise the title and
 * start time decide: the same event is routinely reported by MeetingBar and
 * the Calendar API with different link strings (query parameters, or the event
 * synced into two calendars), so equal title + equal start time means the same
 * meeting. When neither side has a usable time, an empty URL falls back to a
 * title comparison.
 */
export function isSameMeeting(a: MeetingLike, b: MeetingLike): boolean {
  const ua = normalizeMeetingUrl(a.url);
  const ub = normalizeMeetingUrl(b.url);
  if (ua && ub && ua === ub) return true;

  const ta = normalizeMeetingTitle(a.title);
  const tb = normalizeMeetingTitle(b.title);
  if (!ta || ta !== tb) return false;

  const na = normalizeMeetingTime(a.time);
  const nb = normalizeMeetingTime(b.time);
  if (na && nb) return na === nb;

  return !ua || !ub;
}

/**
 * De-duplicate a list of meetings, preserving order. The first occurrence wins,
 * so a triggered meeting passed first is kept over its calendar counterpart.
 */
export function dedupeMeetings<T extends MeetingLike>(meetings: T[]): T[] {
  const result: T[] = [];
  for (const meeting of meetings) {
    if (result.some((existing) => isSameMeeting(existing, meeting))) continue;
    result.push(meeting);
  }
  return result;
}
