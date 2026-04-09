import * as childProcess from "child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  utimesSync,
  writeFileSync,
} from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  buildNotificationApp,
  createProfileTemplate,
  needsRebuild,
  parseKeyValuePairs,
  renderInfoPlist,
  renderTemplate,
  resolveNotificationRequest,
  resolveProfilePaths,
  sendNotificationAppRequest,
  validateProfile,
} from "./notifications";

vi.mock("child_process", () => ({
  execFileSync: vi.fn(() => Buffer.from("")),
}));

describe("notifications framework helpers", () => {
  const tempDirs: string[] = [];

  afterEach(() => {
    vi.restoreAllMocks();
    for (const dir of tempDirs.splice(0)) {
      rmSync(dir, { force: true, recursive: true });
    }
  });

  function makeTempDir(): string {
    const dir = mkdtempSync(join(tmpdir(), "notify-framework-"));
    tempDirs.push(dir);
    return dir;
  }

  it("renders templates with whitespace-trimmed placeholders", () => {
    expect(
      renderTemplate("Open {{ meet_url }} now", {
        meet_url: "gmeet://meet.google.com/test-room",
      }),
    ).toBe("Open gmeet://meet.google.com/test-room now");
  });

  it("throws when required template keys are missing", () => {
    expect(() => renderTemplate("{{missing}}", {})).toThrow(
      'Missing template value for "missing"',
    );
  });

  it("parses repeated key/value pairs", () => {
    expect(
      parseKeyValuePairs(["url=https://example.com", "title=Hello"]),
    ).toEqual({
      title: "Hello",
      url: "https://example.com",
    });
  });

  it("creates a default profile scaffold", () => {
    expect(createProfileTemplate("meety")).toEqual({
      actions: [],
      bundleId: "com.benbernard.notify.meety",
      defaultAction: {
        kind: "open-url",
        target: "{{url}}",
      },
      displayName: "Meety Notify",
      icon: "icons/meety.icns",
      permissionPrompt:
        "Meety Notify needs notification permission so it can show alerts and run the action attached to a notification when you click it.",
      sound: "default",
    });
  });

  it("validates action id uniqueness and icon type", () => {
    const profile = createProfileTemplate("broken", {
      actions: [
        {
          id: "join",
          kind: "open-url",
          target: "{{url}}",
          title: "Join",
        },
        {
          id: "join",
          kind: "reschedule",
          minutes: 5,
          title: "Snooze",
        },
      ],
      icon: "icons/not-icns.png",
    });

    expect(validateProfile("broken", profile)).toEqual([
      'Profile "broken" icon "icons/not-icns.png" must point to an .icns file.',
      'Profile "broken" reuses action id "join". Action ids must be unique.',
    ]);
  });

  it("resolves notification requests with rendered actions", () => {
    const profile = createProfileTemplate("meety", {
      defaultAction: {
        kind: "open-url",
        target: "{{meet_url}}",
      },
      actions: [
        {
          id: "join",
          kind: "open-url",
          target: "{{meet_url}}",
          title: "Join",
        },
        {
          id: "snooze",
          kind: "reschedule",
          minutes: 5,
        },
      ],
    });

    const request = resolveNotificationRequest({
      body: "Click to join",
      context: {
        meet_url: "gmeet://meet.google.com/abc-defg-hij",
      },
      notificationId: "test-meeting",
      profile,
      profileName: "meety",
      subtitle: "2:30 PM",
      title: "Design Review",
    });

    expect(request).toEqual({
      actions: [
        {
          id: "join",
          kind: "open-url",
          target: "gmeet://meet.google.com/abc-defg-hij",
          title: "Join",
        },
        {
          id: "snooze",
          kind: "reschedule",
          minutes: 5,
          title: "Snooze 5m",
        },
      ],
      body: "Click to join",
      defaultAction: {
        id: "default",
        kind: "open-url",
        target: "gmeet://meet.google.com/abc-defg-hij",
      },
      notificationId: "test-meeting",
      sound: "default",
      subtitle: "2:30 PM",
      title: "Design Review",
    });
  });

  it("supports informational notifications without click actions", () => {
    const profile = {
      ...createProfileTemplate("meety"),
      actions: [],
      defaultAction: undefined,
    };

    const request = resolveNotificationRequest({
      body: "Meeting starting now",
      context: {},
      notificationId: "test-meeting-info",
      profile,
      profileName: "meety",
      subtitle: "2:30 PM",
      title: "Calendar Block",
    });

    expect(request).toEqual({
      actions: [],
      body: "Meeting starting now",
      defaultAction: undefined,
      notificationId: "test-meeting-info",
      sound: "default",
      subtitle: "2:30 PM",
      title: "Calendar Block",
    });
  });

  it("renders Info.plist values safely", () => {
    expect(
      renderInfoPlist({
        actions: [],
        bundleId: "com.benbernard.notify.test",
        displayName: 'Ben & "Friends"',
        icon: "icons/test.icns",
      }),
    ).toContain("Ben &amp; &quot;Friends&quot;");
  });

  it("detects when a built app is stale", () => {
    const homeDir = makeTempDir();
    const notificationsRoot = join(homeDir, "notifications");
    const appDir = join(homeDir, "Applications", "NotificationApps");
    mkdirSync(join(notificationsRoot, "runtime"), { recursive: true });
    mkdirSync(appDir, { recursive: true });

    const manifestPath = join(notificationsRoot, "manifest.json");
    const runtimeSourcePath = join(
      notificationsRoot,
      "runtime",
      "NotifyAgent.swift",
    );
    const iconPath = join(notificationsRoot, "icons", "meety.icns");
    mkdirSync(join(notificationsRoot, "icons"), { recursive: true });
    writeFileSync(manifestPath, "{}");
    writeFileSync(runtimeSourcePath, "// swift");
    writeFileSync(iconPath, "icon");

    const profile = createProfileTemplate("meety");
    const paths = resolveProfilePaths({
      appDir,
      homeDir,
      manifestPath,
      profile,
    });

    mkdirSync(paths.macOSDir, { recursive: true });
    mkdirSync(paths.resourcesDir, { recursive: true });
    writeFileSync(paths.executablePath, "binary");
    writeFileSync(paths.infoPlistPath, "plist");
    writeFileSync(paths.iconDestinationPath, "icon");
    writeFileSync(paths.profileResourcePath, "{}");

    const now = new Date();
    const old = new Date(now.getTime() - 10_000);
    utimesSync(paths.executablePath, now, now);
    utimesSync(paths.infoPlistPath, now, now);
    utimesSync(paths.iconDestinationPath, now, now);
    utimesSync(paths.profileResourcePath, now, now);
    utimesSync(manifestPath, old, old);
    utimesSync(runtimeSourcePath, old, old);
    utimesSync(iconPath, old, old);

    expect(needsRebuild(paths)).toBe(false);

    const future = new Date(now.getTime() + 10_000);
    utimesSync(runtimeSourcePath, future, future);
    expect(needsRebuild(paths)).toBe(true);
  });

  it("does not rebuild forever when the copied icon keeps its original timestamp", () => {
    const homeDir = makeTempDir();
    const notificationsRoot = join(homeDir, "notifications");
    const appDir = join(homeDir, "Applications", "NotificationApps");
    mkdirSync(join(notificationsRoot, "runtime"), { recursive: true });
    mkdirSync(join(notificationsRoot, "icons"), { recursive: true });
    mkdirSync(appDir, { recursive: true });

    const manifestPath = join(notificationsRoot, "manifest.json");
    const runtimeSourcePath = join(
      notificationsRoot,
      "runtime",
      "NotifyAgent.swift",
    );
    const iconPath = join(notificationsRoot, "icons", "meety.icns");
    writeFileSync(manifestPath, "{}");
    writeFileSync(runtimeSourcePath, "// swift");
    writeFileSync(iconPath, "icon");

    const profile = createProfileTemplate("meety");
    const paths = resolveProfilePaths({
      appDir,
      homeDir,
      manifestPath,
      profile,
    });

    mkdirSync(paths.macOSDir, { recursive: true });
    mkdirSync(paths.resourcesDir, { recursive: true });
    writeFileSync(paths.executablePath, "binary");
    writeFileSync(paths.infoPlistPath, "plist");
    writeFileSync(paths.iconDestinationPath, "icon");
    writeFileSync(paths.profileResourcePath, "{}");

    const now = new Date();
    const earlier = new Date(now.getTime() - 20_000);
    const later = new Date(now.getTime() - 10_000);

    utimesSync(iconPath, earlier, earlier);
    utimesSync(paths.iconDestinationPath, earlier, earlier);
    utimesSync(manifestPath, later, later);
    utimesSync(runtimeSourcePath, later, later);
    utimesSync(paths.executablePath, now, now);
    utimesSync(paths.infoPlistPath, now, now);
    utimesSync(paths.profileResourcePath, now, now);

    expect(needsRebuild(paths)).toBe(false);
  });

  it("builds an app bundle layout and invokes swiftc/codesign", () => {
    const homeDir = makeTempDir();
    const notificationsRoot = join(homeDir, "notifications");
    const appDir = join(homeDir, "Applications", "NotificationApps");
    mkdirSync(join(notificationsRoot, "runtime"), { recursive: true });
    mkdirSync(join(notificationsRoot, "icons"), { recursive: true });
    mkdirSync(appDir, { recursive: true });

    const manifestPath = join(notificationsRoot, "manifest.json");
    const runtimeSourcePath = join(
      notificationsRoot,
      "runtime",
      "NotifyAgent.swift",
    );
    const iconPath = join(notificationsRoot, "icons", "meety.icns");
    writeFileSync(manifestPath, "{}\n");
    writeFileSync(runtimeSourcePath, "// swift runtime\n");
    writeFileSync(iconPath, "fake icon");

    const execSpy = childProcess.execFileSync as unknown as ReturnType<
      typeof vi.fn
    >;
    execSpy.mockClear();

    const profile = createProfileTemplate("meety");
    const paths = buildNotificationApp({
      appDir,
      homeDir,
      manifestPath,
      profile,
      profileName: "meety",
    });

    expect(existsSync(paths.infoPlistPath)).toBe(true);
    expect(existsSync(paths.profileResourcePath)).toBe(true);
    expect(readFileSync(paths.profileResourcePath, "utf8")).toContain(
      '"profileName": "meety"',
    );
    expect(readFileSync(paths.profileResourcePath, "utf8")).toContain(
      '"permissionPrompt": "Meety Notify needs notification permission so it can show alerts and run the action attached to a notification when you click it."',
    );
    expect(readFileSync(paths.infoPlistPath, "utf8")).toContain(
      "<string>com.benbernard.notify.meety</string>",
    );
    expect(execSpy).toHaveBeenCalledWith(
      "swiftc",
      expect.arrayContaining([runtimeSourcePath, "-o", paths.executablePath]),
      { stdio: "inherit" },
    );
    expect(execSpy).toHaveBeenCalledWith(
      "/usr/bin/codesign",
      ["--force", "--deep", "--sign", "-", paths.bundleDir],
      { stdio: "inherit" },
    );
  });

  it("opens the app bundle through LaunchServices when sending", () => {
    const execSpy = childProcess.execFileSync as unknown as ReturnType<
      typeof vi.fn
    >;
    execSpy.mockClear();

    sendNotificationAppRequest(
      {
        appDir: "/tmp/apps",
        bundleDir: "/tmp/apps/Meety Notify.app",
        contentsDir: "/tmp/apps/Meety Notify.app/Contents",
        executablePath:
          "/tmp/apps/Meety Notify.app/Contents/MacOS/notify-agent",
        iconDestinationPath:
          "/tmp/apps/Meety Notify.app/Contents/Resources/AppIcon.icns",
        iconSourcePath: "/tmp/notifications/icons/meety.icns",
        infoPlistPath: "/tmp/apps/Meety Notify.app/Contents/Info.plist",
        macOSDir: "/tmp/apps/Meety Notify.app/Contents/MacOS",
        manifestPath: "/tmp/notifications/manifest.json",
        profileResourcePath:
          "/tmp/apps/Meety Notify.app/Contents/Resources/profile.json",
        resourcesDir: "/tmp/apps/Meety Notify.app/Contents/Resources",
        runtimeSourcePath: "/tmp/notifications/runtime/NotifyAgent.swift",
      },
      {
        actions: [],
        body: "Click to join",
        notificationId: "meeting-123",
        sound: "default",
        subtitle: "2:30 PM",
        title: "Design Review",
      },
    );

    expect(execSpy).toHaveBeenCalledWith(
      "/usr/bin/open",
      [
        "-n",
        "/tmp/apps/Meety Notify.app",
        "--args",
        "--send-base64",
        expect.any(String),
      ],
      { stdio: "inherit" },
    );
  });
});
