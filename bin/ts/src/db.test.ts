import { describe, expect, it } from "vitest";
import { generateFilename } from "./db";

describe("db - Filename Generation", () => {
  it("should convert to lowercase", () => {
    expect(generateFilename("MyFile")).toBe("myfile.zip");
    expect(generateFilename("UPPERCASE")).toBe("uppercase.zip");
  });

  it("should replace spaces with dashes", () => {
    expect(generateFilename("my file name")).toBe("my-file-name.zip");
    expect(generateFilename("multiple   spaces")).toBe("multiple-spaces.zip");
  });

  it("should replace non-alphanumeric characters with dashes", () => {
    expect(generateFilename("file!@#$%name")).toBe("file-name.zip");
    expect(generateFilename("test/path\\file")).toBe("test-path-file.zip");
    expect(generateFilename("file(1).txt")).toBe("file-1-txt.zip");
  });

  it("should remove leading and trailing dashes", () => {
    expect(generateFilename("---file---")).toBe("file.zip");
    expect(generateFilename("@@@file@@@")).toBe("file.zip");
    expect(generateFilename("   file   ")).toBe("file.zip");
  });

  it("should use fallback for empty or all-special-char strings", () => {
    expect(generateFilename("")).toBe("download.zip");
    expect(generateFilename("!!!")).toBe("download.zip");
    expect(generateFilename("@#$%^&*()")).toBe("download.zip");
    expect(generateFilename("   ")).toBe("download.zip");
  });

  it("should handle complex real-world examples", () => {
    expect(generateFilename("My Cool Project (2024)")).toBe(
      "my-cool-project-2024.zip",
    );
    expect(generateFilename("Node.js v20.1.0")).toBe("node-js-v20-1-0.zip");
    expect(generateFilename("README.md")).toBe("readme-md.zip");
    expect(generateFilename("user@example.com")).toBe("user-example-com.zip");
  });

  it("should collapse multiple dashes", () => {
    expect(generateFilename("file---name")).toBe("file-name.zip");
    expect(generateFilename("a  !@#  b")).toBe("a-b.zip");
  });

  it("should handle strings with only alphanumeric characters", () => {
    expect(generateFilename("file123")).toBe("file123.zip");
    expect(generateFilename("test")).toBe("test.zip");
    expect(generateFilename("abc123xyz")).toBe("abc123xyz.zip");
  });
});
