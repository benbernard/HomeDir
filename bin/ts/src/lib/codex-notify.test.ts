import { describe, expect, it } from "vitest";
import {
  buildCodexNotification,
  parseCodexNotifyPayload,
} from "./codex-notify";

describe("codex notification helpers", () => {
  it("parses the Codex payload JSON", () => {
    expect(
      parseCodexNotifyPayload(
        '{"type":"agent-turn-complete","client":"codex-exec"}',
      ),
    ).toEqual({
      client: "codex-exec",
      type: "agent-turn-complete",
    });
  });

  it("rejects non-object payloads", () => {
    expect(() => parseCodexNotifyPayload('["nope"]')).toThrow(
      "Codex notification payload must be a JSON object.",
    );
  });

  it("falls back to the input preview when the assistant reply is too generic", () => {
    expect(
      buildCodexNotification({
        "input-messages": ["Reply with the single word done."],
        "last-assistant-message": "done",
        type: "agent-turn-complete",
      }),
    ).toMatchObject({
      body: "Finished: Reply with the single word done.",
      title: "Codex finished",
    });
  });

  it("uses the assistant preview when it contains real content", () => {
    expect(
      buildCodexNotification({
        cwd: "/Users/benbernard/repos/tally",
        "input-messages": ["Fix the flaky test"],
        "last-assistant-message":
          "Implemented the notification adapter and verified the send path.",
        type: "agent-turn-complete",
      }),
    ).toEqual({
      body: "Implemented the notification adapter and verified the send path.",
      context: {
        client: "codex",
        cwd: "/Users/benbernard/repos/tally",
        event_type: "agent-turn-complete",
      },
      subtitle: "tally",
      title: "Codex finished",
    });
  });

  it("truncates long previews and humanizes unknown event types", () => {
    const notification = buildCodexNotification({
      "input-messages": ["This is a long prompt ".repeat(20)],
      type: "session-start",
    });

    expect(notification.title).toBe("Codex Session start");
    expect(notification.body.endsWith("…")).toBe(true);
  });
});
