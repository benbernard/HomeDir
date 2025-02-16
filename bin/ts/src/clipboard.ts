import { execSync } from "child_process";

export function getHtmlFromClipboard(): string {
  try {
    return execSync(
      `osascript -e 'the clipboard as «class HTML»' | perl -ne 'print chr foreach unpack("C*",pack("H*",substr($_,11,-3)))'`,
    ).toString();
  } catch (error) {
    return "";
  }
}
