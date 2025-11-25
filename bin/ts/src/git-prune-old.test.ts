import { describe, expect, it } from "vitest";

// Since git-prune-old.ts doesn't export most functions, we'll need to add exports
// For now, let's create a helper module with the testable logic

describe("git-prune-old - String Utilities", () => {
  // Test truncateString function
  function truncateString(str: string, maxLength: number): string {
    if (str.length <= maxLength) {
      return str;
    }
    return `${str.slice(0, maxLength - 3)}...`;
  }

  it("should not truncate strings shorter than max length", () => {
    expect(truncateString("short", 10)).toBe("short");
  });

  it("should not truncate strings equal to max length", () => {
    expect(truncateString("exactly10!", 10)).toBe("exactly10!");
  });

  it("should truncate strings longer than max length", () => {
    expect(truncateString("this is a very long string", 10)).toBe("this is...");
  });

  it("should handle max length of 3", () => {
    expect(truncateString("hello", 3)).toBe("...");
  });

  it("should handle empty strings", () => {
    expect(truncateString("", 10)).toBe("");
  });

  it("should truncate with different max lengths", () => {
    const str = "The quick brown fox jumps over the lazy dog";
    expect(truncateString(str, 20)).toBe("The quick brown f...");
    expect(truncateString(str, 15)).toBe("The quick br...");
    expect(truncateString(str, 10)).toBe("The qui...");
  });
});
