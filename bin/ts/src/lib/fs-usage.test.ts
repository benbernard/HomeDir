import { describe, expect, test } from "vitest";
import {
  classifyFsUsageLine,
  extractFsUsageCall,
  lineMentionsExactPath,
  lineMentionsPathWithinDirectory,
  lineMentionsTargetFamily,
} from "./fs-usage";

const target = "/Users/example/.claude/settings.json";

describe("fs_usage parsing", () => {
  test("matches the exact target but not similarly named files", () => {
    expect(
      lineMentionsExactPath(`12:00 stat64 ${target} 0.001 Claude.1`, target),
    ).toBe(true);
    expect(
      lineMentionsExactPath(
        `12:00 stat64 ${target}.tmp 0.001 Claude.1`,
        target,
      ),
    ).toBe(false);
    expect(
      lineMentionsExactPath(
        "12:00 stat64 /Users/example/project/settings.json 0.001 git.1",
        target,
      ),
    ).toBe(false);
  });

  test("matches target-family temporary files", () => {
    expect(
      lineMentionsTargetFamily(
        "12:00 openat /Users/example/.claude/.settings.json.123.tmp 0.001 tally.1",
        target,
      ),
    ).toBe(true);
    expect(
      lineMentionsTargetFamily(
        "12:00 openat /Users/example/.claude/settings.json.lock 0.001 tally.1",
        target,
      ),
    ).toBe(true);
    expect(
      lineMentionsTargetFamily(
        "12:00 openat /Users/example/.claude/session.json 0.001 tally.1",
        target,
      ),
    ).toBe(false);
  });

  test("recognizes paths inside the target directory", () => {
    expect(
      lineMentionsPathWithinDirectory(
        "12:00 rename /Users/example/.claude/random.tmp 0.001 writer.1",
        "/Users/example/.claude",
      ),
    ).toBe(true);
    expect(
      lineMentionsPathWithinDirectory(
        "12:00 rename /Users/example/.claude.json 0.001 writer.1",
        "/Users/example/.claude",
      ),
    ).toBe(false);
  });

  test("extracts and classifies metadata calls", () => {
    const line = `11:49:10.156363 getattrlist ${target} 0.000003 2.1.218.67104033`;
    expect(extractFsUsageCall(line)).toBe("getattrlist");
    expect(classifyFsUsageLine(line)).toBe("metadata");
  });

  test("classifies read and write opens from their flags", () => {
    expect(
      classifyFsUsageLine(
        `12:00 openat F=7 (R______________) ${target} 0.001 Claude.1`,
      ),
    ).toBe("read");
    expect(
      classifyFsUsageLine(
        `12:00 openat F=7 (_WCA___________) ${target} 0.001 Claude.1`,
      ),
    ).toBe("write");
  });

  test("classifies mutations as writes", () => {
    expect(
      classifyFsUsageLine(
        `12:00 rename /tmp/settings ${target} 0.001 Claude.1`,
      ),
    ).toBe("write");
    expect(
      classifyFsUsageLine(`12:00 WrData[A] B=0x1000 ${target} 0.001 Claude.1`),
    ).toBe("write");
  });
});
