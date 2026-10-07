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
 * Whether two meetings refer to the same event.
 *
 * Two non-empty URLs that match are authoritative. When either side has no
 * usable URL, fall back to a normalized title comparison.
 */
export function isSameMeeting(a: MeetingLike, b: MeetingLike): boolean {
  const ua = normalizeMeetingUrl(a.url);
  const ub = normalizeMeetingUrl(b.url);
  if (ua && ub) return ua === ub;
  return normalizeMeetingTitle(a.title) === normalizeMeetingTitle(b.title);
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
