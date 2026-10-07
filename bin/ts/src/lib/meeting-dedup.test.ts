import { describe, expect, test } from "vitest";
import {
  dedupeMeetings,
  isSameMeeting,
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
        { title: "Standup", url: "https://meet.google.com/aaa-bbbb-ccc", time: "" },
        { title: "Standup", url: "https://meet.google.com/ddd-eeee-fff", time: "" },
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
    const a = { title: "Design Review", url: "https://meet.google.com/x", time: "" };
    const b = { title: "Team Standup", url: "https://meet.google.com/y", time: "" };
    expect(dedupeMeetings([a, b])).toEqual([a, b]);
  });
});
