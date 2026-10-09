import { describe, expect, test } from "vitest";
import {
  dedupeMeetings,
  isSameMeeting,
  normalizeMeetingTime,
  normalizeMeetingTitle,
  normalizeMeetingUrl,
} from "./meeting-dedup";

const meet = "https://meet.google.com/qmo-rhok-ijf";

describe("normalizeMeetingUrl", () => {
  test("treats meet https and gmeet as equivalent", () => {
    expect(normalizeMeetingUrl(meet)).toBe(
      "gmeet://meet.google.com/qmo-rhok-ijf",
    );
    expect(normalizeMeetingUrl("gmeet://meet.google.com/qmo-rhok-ijf")).toBe(
      "gmeet://meet.google.com/qmo-rhok-ijf",
    );
  });

  test("treats the no-link placeholder as empty", () => {
    expect(normalizeMeetingUrl("EMPTY")).toBe("");
    expect(normalizeMeetingUrl("")).toBe("");
  });
});

describe("normalizeMeetingTitle", () => {
  test("ignores punctuation differences between sources", () => {
    expect(normalizeMeetingTitle("Alex <> Kim")).toBe(
      normalizeMeetingTitle("Alex Kim"),
    );
    expect(normalizeMeetingTitle("Project Sync: Weekly — Planning")).toBe(
      normalizeMeetingTitle("Project Sync: Weekly Planning"),
    );
  });
});

describe("normalizeMeetingTime", () => {
  test("parses MeetingBar and RFC3339 times to the same key", () => {
    expect(
      normalizeMeetingTime("Thursday, October 8, 2026 at 4:00:00 PM"),
    ).toBe(normalizeMeetingTime("2026-10-08T16:00:00-07:00"));
  });

  test("ignores seconds and the narrow no-break space MeetingBar emits", () => {
    expect(
      normalizeMeetingTime("Thursday, October 8, 2026 at 4:00:00\u202fPM"),
    ).toBe(normalizeMeetingTime("Thursday, October 8, 2026 at 4:00:00 PM"));
  });

  test("distinguishes different start times", () => {
    expect(
      normalizeMeetingTime("Thursday, October 8, 2026 at 4:00:00 PM"),
    ).not.toBe(normalizeMeetingTime("Thursday, October 8, 2026 at 4:30:00 PM"));
  });

  test("passes through unparseable input", () => {
    expect(normalizeMeetingTime("sometime soon")).toBe("sometime soon");
    expect(normalizeMeetingTime("")).toBe("");
  });
});

describe("isSameMeeting", () => {
  test("matches the same event when titles differ but URLs agree", () => {
    expect(
      isSameMeeting(
        { title: "Alex Kim", url: meet, time: "" },
        { title: "Alex <> Kim", url: meet, time: "" },
      ),
    ).toBe(true);
  });

  test("does not match distinct meetings that share a title", () => {
    expect(
      isSameMeeting(
        {
          title: "Standup",
          url: "https://meet.google.com/aaa-bbbb-ccc",
          time: "",
        },
        {
          title: "Standup",
          url: "https://meet.google.com/ddd-eeee-fff",
          time: "",
        },
      ),
    ).toBe(false);
  });

  test("falls back to title when one side has no URL", () => {
    expect(
      isSameMeeting(
        { title: "Alex Kim", url: "", time: "" },
        { title: "Alex <> Kim", url: meet, time: "" },
      ),
    ).toBe(true);
  });

  test("matches the same event reported with different links at the same time", () => {
    expect(
      isSameMeeting(
        {
          title: "Project Sync",
          url: "https://meet.google.com/aaa-bbbb-ccc?hs=224",
          time: "Thursday, May 21, 2026 at 2:30:00 PM",
        },
        {
          title: "Project Sync",
          url: "https://meet.google.com/aaa-bbbb-ccc",
          time: "2026-05-21T14:30:00-07:00",
        },
      ),
    ).toBe(true);
  });

  test("does not match the same title at different times", () => {
    expect(
      isSameMeeting(
        {
          title: "Project Sync",
          url: "https://meet.google.com/aaa-bbbb-ccc",
          time: "Thursday, May 21, 2026 at 2:30:00 PM",
        },
        {
          title: "Project Sync",
          url: "https://meet.google.com/ddd-eeee-fff",
          time: "2026-05-21T15:00:00-07:00",
        },
      ),
    ).toBe(false);
  });
});

describe("dedupeMeetings", () => {
  test("collapses the duplicate triggered/calendar pair, keeping the first", () => {
    const triggered = { title: "Alex Kim", url: meet, time: "9:00 AM" };
    const calendar = { title: "Alex <> Kim", url: meet, time: "9:00 AM" };
    const other = {
      title: "Team Standup",
      url: "https://meet.google.com/zmh-miox-aos",
      time: "9:30 AM",
    };

    const result = dedupeMeetings([triggered, calendar, other]);
    expect(result).toEqual([triggered, other]);
  });

  test("keeps genuinely different meetings", () => {
    const a = {
      title: "Design Review",
      url: "https://meet.google.com/x",
      time: "",
    };
    const b = {
      title: "Team Standup",
      url: "https://meet.google.com/y",
      time: "",
    };
    expect(dedupeMeetings([a, b])).toEqual([a, b]);
  });

  test("collapses the same event shared across two calendars", () => {
    const triggered = {
      title: "Project Sync",
      url: "https://meet.google.com/aaa-bbbb-ccc?hs=224",
      time: "Thursday, May 21, 2026 at 2:30:00 PM",
    };
    const calendar = {
      title: "Project Sync",
      url: "https://meet.google.com/aaa-bbbb-ccc",
      time: "2026-05-21T14:30:00-07:00",
    };
    expect(dedupeMeetings([triggered, calendar])).toEqual([triggered]);
  });
});
