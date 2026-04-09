import * as childProcess from "child_process";
import { randomUUID } from "crypto";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "fs";
import { homedir } from "os";
import { dirname, isAbsolute, join, resolve } from "path";

export const NOTIFICATIONS_DIR_NAME = "notifications";
export const NOTIFICATIONS_MANIFEST_NAME = "manifest.json";
export const NOTIFY_AGENT_EXECUTABLE = "notify-agent";
export const NOTIFY_AGENT_SOURCE_PATH = join(
  NOTIFICATIONS_DIR_NAME,
  "runtime",
  "NotifyAgent.swift",
);
export const DEFAULT_NOTIFICATION_APP_DIR = join(
  "Applications",
  "NotificationApps",
);

export type NotificationActionDefinition =
  | {
      id?: string;
      title?: string;
      kind: "open-url";
      target: string;
    }
  | {
      id?: string;
      title?: string;
      kind: "run-command";
      argv: string[];
    }
  | {
      id?: string;
      title?: string;
      kind: "reschedule";
      minutes: number;
    };

export interface NotificationProfile {
  bundleId: string;
  displayName: string;
  icon: string;
  permissionPrompt?: string;
  sound?: string;
  defaultAction?: NotificationActionDefinition;
  actions?: NotificationActionDefinition[];
}

export interface NotificationManifest {
  $schemaVersion: number;
  profiles: Record<string, NotificationProfile>;
}

export type ResolvedNotificationAction =
  | {
      id: string;
      title?: string;
      kind: "open-url";
      target: string;
    }
  | {
      id: string;
      title?: string;
      kind: "run-command";
      argv: string[];
    }
  | {
      id: string;
      title?: string;
      kind: "reschedule";
      minutes: number;
    };

export interface ResolvedNotificationRequest {
  notificationId: string;
  title: string;
  subtitle?: string;
  body: string;
  sound?: string;
  defaultAction?: ResolvedNotificationAction;
  actions: ResolvedNotificationAction[];
}

export interface NotificationAppPaths {
  appDir: string;
  bundleDir: string;
  contentsDir: string;
  resourcesDir: string;
  macOSDir: string;
  executablePath: string;
  infoPlistPath: string;
  iconSourcePath: string;
  iconDestinationPath: string;
  manifestPath: string;
  profileResourcePath: string;
  runtimeSourcePath: string;
}

export interface ResolvePathsOptions {
  homeDir?: string;
  appDir?: string;
  manifestPath?: string;
  profile: NotificationProfile;
}

export interface BuildNotificationAppOptions extends ResolvePathsOptions {
  profileName: string;
}

export interface ResolveNotificationRequestOptions {
  profileName: string;
  profile: NotificationProfile;
  title: string;
  subtitle?: string;
  body?: string;
  sound?: string;
  context?: Record<string, string>;
  notificationId?: string;
}

export interface CreateProfileOptions {
  displayName?: string;
  bundleId?: string;
  icon?: string;
  permissionPrompt?: string;
  defaultAction?: NotificationActionDefinition;
  actions?: NotificationActionDefinition[];
  sound?: string;
}

export function getNotificationsRoot(homeDir = homedir()): string {
  return join(homeDir, NOTIFICATIONS_DIR_NAME);
}

export function getNotificationsManifestPath(homeDir = homedir()): string {
  return join(getNotificationsRoot(homeDir), NOTIFICATIONS_MANIFEST_NAME);
}

export function getNotifyAgentSourcePath(homeDir = homedir()): string {
  return join(homeDir, NOTIFY_AGENT_SOURCE_PATH);
}

export function getDefaultNotificationAppDir(homeDir = homedir()): string {
  return join(homeDir, DEFAULT_NOTIFICATION_APP_DIR);
}

export function loadNotificationsManifest(
  manifestPath = getNotificationsManifestPath(),
): NotificationManifest {
  const raw = readFileSync(manifestPath, "utf8");
  return JSON.parse(raw) as NotificationManifest;
}

export function saveNotificationsManifest(
  manifest: NotificationManifest,
  manifestPath = getNotificationsManifestPath(),
): void {
  mkdirSync(dirname(manifestPath), { recursive: true });
  const sortedProfiles = Object.fromEntries(
    Object.entries(manifest.profiles).sort(([left], [right]) =>
      left.localeCompare(right),
    ),
  );
  const nextManifest: NotificationManifest = {
    $schemaVersion: manifest.$schemaVersion,
    profiles: sortedProfiles,
  };
  writeFileSync(
    manifestPath,
    `${JSON.stringify(nextManifest, null, 2)}\n`,
    "utf8",
  );
}

export function parseKeyValuePairs(
  entries: string[] | undefined,
): Record<string, string> {
  const context: Record<string, string> = {};
  for (const entry of entries ?? []) {
    const separatorIndex = entry.indexOf("=");
    if (separatorIndex <= 0) {
      throw new Error(
        `Invalid --data value "${entry}". Expected key=value format.`,
      );
    }

    const key = entry.slice(0, separatorIndex).trim();
    const value = entry.slice(separatorIndex + 1);
    if (!key) {
      throw new Error(
        `Invalid --data value "${entry}". Keys may not be empty.`,
      );
    }

    context[key] = value;
  }
  return context;
}

export function renderTemplate(
  template: string,
  context: Record<string, string>,
): string {
  return template.replace(/\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}/g, (_, key) => {
    if (!(key in context)) {
      throw new Error(`Missing template value for "${key}" in "${template}"`);
    }
    return context[key];
  });
}

export function createProfileTemplate(
  name: string,
  options: CreateProfileOptions = {},
): NotificationProfile {
  const normalizedName = name.trim().toLowerCase();
  if (!/^[a-z0-9][a-z0-9-]*$/.test(normalizedName)) {
    throw new Error(`Profile names must match [a-z0-9-]. Received "${name}".`);
  }

  const displayName =
    options.displayName ?? `${toDisplayName(normalizedName)} Notify`;

  return {
    bundleId:
      options.bundleId ??
      `com.benbernard.notify.${normalizedName.replace(/[^a-z0-9]/g, "")}`,
    displayName,
    icon: options.icon ?? `icons/${normalizedName}.icns`,
    permissionPrompt:
      options.permissionPrompt ?? defaultPermissionPrompt(displayName),
    sound: options.sound ?? "default",
    defaultAction: options.defaultAction ?? {
      kind: "open-url",
      target: "{{url}}",
    },
    actions: options.actions ?? [],
  };
}

export function validateProfile(
  name: string,
  profile: NotificationProfile,
): string[] {
  const errors: string[] = [];

  if (!/^[a-z0-9][a-z0-9-]*$/.test(name)) {
    errors.push(
      `Profile "${name}" must match [a-z0-9-] to keep file and bundle names predictable.`,
    );
  }

  if (!profile.bundleId.trim()) {
    errors.push(`Profile "${name}" is missing a bundleId.`);
  } else if (!/^[A-Za-z0-9.]+$/.test(profile.bundleId)) {
    errors.push(
      `Profile "${name}" bundleId "${profile.bundleId}" contains unsupported characters.`,
    );
  }

  if (!profile.displayName.trim()) {
    errors.push(`Profile "${name}" is missing a displayName.`);
  }

  if (
    profile.permissionPrompt != null &&
    profile.permissionPrompt.trim().length === 0
  ) {
    errors.push(
      `Profile "${name}" permissionPrompt must be omitted or contain text.`,
    );
  }

  if (!profile.icon.trim()) {
    errors.push(`Profile "${name}" is missing an icon path.`);
  } else if (!profile.icon.endsWith(".icns")) {
    errors.push(
      `Profile "${name}" icon "${profile.icon}" must point to an .icns file.`,
    );
  }

  if ((profile.actions?.length ?? 0) > 4) {
    errors.push(
      `Profile "${name}" defines more than 4 custom actions, which is beyond the native notification limit.`,
    );
  }

  if (profile.defaultAction) {
    validateActionDefinition(
      `Profile "${name}" defaultAction`,
      profile.defaultAction,
      errors,
      false,
    );
  }

  const seenActionIds = new Set<string>();
  for (const action of profile.actions ?? []) {
    const actionId = action.id?.trim();
    if (!actionId) {
      errors.push(`Profile "${name}" has an action without an id.`);
      continue;
    }

    if (seenActionIds.has(actionId)) {
      errors.push(
        `Profile "${name}" reuses action id "${actionId}". Action ids must be unique.`,
      );
    }
    seenActionIds.add(actionId);

    validateActionDefinition(
      `Profile "${name}" action "${actionId}"`,
      action,
      errors,
      true,
    );
  }

  return errors;
}

export function resolveProfilePaths(
  options: ResolvePathsOptions,
): NotificationAppPaths {
  const homeDir = options.homeDir ?? homedir();
  const manifestPath =
    options.manifestPath ?? getNotificationsManifestPath(homeDir);
  const appDir = options.appDir ?? getDefaultNotificationAppDir(homeDir);
  const bundleDir = join(appDir, `${options.profile.displayName}.app`);
  const contentsDir = join(bundleDir, "Contents");
  const resourcesDir = join(contentsDir, "Resources");
  const macOSDir = join(contentsDir, "MacOS");

  return {
    appDir,
    bundleDir,
    contentsDir,
    resourcesDir,
    macOSDir,
    executablePath: join(macOSDir, NOTIFY_AGENT_EXECUTABLE),
    infoPlistPath: join(contentsDir, "Info.plist"),
    iconSourcePath: resolveManifestPath(manifestPath, options.profile.icon),
    iconDestinationPath: join(resourcesDir, "AppIcon.icns"),
    manifestPath,
    profileResourcePath: join(resourcesDir, "profile.json"),
    runtimeSourcePath: getNotifyAgentSourcePath(homeDir),
  };
}

function deriveBundleVersion(paths: NotificationAppPaths): string {
  const sourcePaths = [
    paths.manifestPath,
    paths.runtimeSourcePath,
    paths.iconSourcePath,
  ];
  const latestSourceMtimeMs = Math.max(
    ...sourcePaths.map((sourcePath) =>
      Math.floor(statSync(sourcePath).mtimeMs),
    ),
  );
  return String(latestSourceMtimeMs);
}

export function renderInfoPlist(
  profile: NotificationProfile,
  bundleVersion = "1",
): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${xmlEscape(profile.displayName)}</string>
  <key>CFBundleExecutable</key>
  <string>${NOTIFY_AGENT_EXECUTABLE}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>CFBundleIdentifier</key>
  <string>${xmlEscape(profile.bundleId)}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${xmlEscape(profile.displayName)}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>${xmlEscape(bundleVersion)}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
`;
}

export function needsRebuild(paths: NotificationAppPaths): boolean {
  const expectedOutputs = [
    paths.bundleDir,
    paths.executablePath,
    paths.infoPlistPath,
    paths.iconDestinationPath,
    paths.profileResourcePath,
  ];

  if (expectedOutputs.some((path) => !existsSync(path))) {
    return true;
  }

  const stalePairs: Array<[inputPath: string, outputPath: string]> = [
    [paths.runtimeSourcePath, paths.executablePath],
    [paths.manifestPath, paths.infoPlistPath],
    [paths.manifestPath, paths.profileResourcePath],
    [paths.iconSourcePath, paths.iconDestinationPath],
  ];

  return stalePairs.some(
    ([inputPath, outputPath]) =>
      statSync(inputPath).mtimeMs > statSync(outputPath).mtimeMs,
  );
}

export function buildNotificationApp(
  options: BuildNotificationAppOptions,
): NotificationAppPaths {
  const validationErrors = validateProfile(
    options.profileName,
    options.profile,
  );
  if (validationErrors.length > 0) {
    throw new Error(validationErrors.join("\n"));
  }

  const paths = resolveProfilePaths(options);

  if (!existsSync(paths.iconSourcePath)) {
    throw new Error(
      `Icon for profile "${options.profileName}" was not found at ${paths.iconSourcePath}`,
    );
  }

  if (!existsSync(paths.runtimeSourcePath)) {
    throw new Error(
      `Swift runtime source is missing at ${paths.runtimeSourcePath}.`,
    );
  }

  rmSync(paths.bundleDir, { force: true, recursive: true });
  mkdirSync(paths.macOSDir, { recursive: true });
  mkdirSync(paths.resourcesDir, { recursive: true });

  writeFileSync(
    paths.infoPlistPath,
    renderInfoPlist(options.profile, deriveBundleVersion(paths)),
    "utf8",
  );
  writeFileSync(
    paths.profileResourcePath,
    `${JSON.stringify(
      {
        profileName: options.profileName,
        bundleId: options.profile.bundleId,
        displayName: options.profile.displayName,
        permissionPrompt: emptyToUndefined(options.profile.permissionPrompt),
      },
      null,
      2,
    )}\n`,
    "utf8",
  );
  copyFileSync(paths.iconSourcePath, paths.iconDestinationPath);

  childProcess.execFileSync(
    "swiftc",
    [
      paths.runtimeSourcePath,
      "-o",
      paths.executablePath,
      "-framework",
      "AppKit",
      "-framework",
      "UserNotifications",
    ],
    { stdio: "inherit" },
  );

  try {
    childProcess.execFileSync(
      "/usr/bin/codesign",
      ["--force", "--deep", "--sign", "-", paths.bundleDir],
      { stdio: "inherit" },
    );
  } catch {
    // Ad-hoc signing is helpful but not required for local development.
  }

  return paths;
}

export function resolveNotificationRequest(
  options: ResolveNotificationRequestOptions,
): ResolvedNotificationRequest {
  const validationErrors = validateProfile(
    options.profileName,
    options.profile,
  );
  if (validationErrors.length > 0) {
    throw new Error(validationErrors.join("\n"));
  }

  const context = options.context ?? {};
  const actions = (options.profile.actions ?? []).map((action, index) =>
    resolveAction(action.id ?? `action-${index + 1}`, action, context, true),
  );

  return {
    notificationId:
      options.notificationId ?? `${options.profileName}-${randomUUID()}`,
    title: options.title,
    subtitle: emptyToUndefined(options.subtitle),
    body: options.body ?? "",
    sound: emptyToUndefined(options.sound ?? options.profile.sound),
    defaultAction: options.profile.defaultAction
      ? resolveAction("default", options.profile.defaultAction, context, false)
      : undefined,
    actions,
  };
}

export function sendNotificationAppRequest(
  paths: NotificationAppPaths,
  request: ResolvedNotificationRequest,
): void {
  const encodedRequest = Buffer.from(JSON.stringify(request), "utf8").toString(
    "base64",
  );
  childProcess.execFileSync(
    "/usr/bin/open",
    ["-n", paths.bundleDir, "--args", "--send-base64", encodedRequest],
    { stdio: "inherit" },
  );
}

function resolveAction(
  id: string,
  action: NotificationActionDefinition,
  context: Record<string, string>,
  requireTitle: boolean,
): ResolvedNotificationAction {
  const title = action.title
    ? renderTemplate(action.title, context)
    : requireTitle
      ? defaultActionTitle(action)
      : undefined;

  switch (action.kind) {
    case "open-url":
      return {
        id,
        title,
        kind: "open-url",
        target: renderTemplate(action.target, context),
      };
    case "run-command":
      return {
        id,
        title,
        kind: "run-command",
        argv: action.argv.map((part) => renderTemplate(part, context)),
      };
    case "reschedule":
      return {
        id,
        title,
        kind: "reschedule",
        minutes: action.minutes,
      };
  }
}

function validateActionDefinition(
  prefix: string,
  action: NotificationActionDefinition,
  errors: string[],
  requireTitle: boolean,
): void {
  if (
    requireTitle &&
    !defaultActionTitle(action).trim() &&
    !action.title?.trim()
  ) {
    errors.push(`${prefix} must define a title.`);
  }

  switch (action.kind) {
    case "open-url":
      if (!action.target.trim()) {
        errors.push(`${prefix} must define a non-empty target.`);
      }
      break;
    case "run-command":
      if (action.argv.length === 0 || !action.argv[0].trim()) {
        errors.push(`${prefix} must define a non-empty argv array.`);
      }
      break;
    case "reschedule":
      if (!Number.isInteger(action.minutes) || action.minutes <= 0) {
        errors.push(`${prefix} must define a positive integer minute count.`);
      }
      break;
  }
}

function resolveManifestPath(manifestPath: string, targetPath: string): string {
  if (isAbsolute(targetPath)) {
    return targetPath;
  }
  return resolve(dirname(manifestPath), targetPath);
}

function toDisplayName(value: string): string {
  return value
    .split("-")
    .filter(Boolean)
    .map((part) => part[0].toUpperCase() + part.slice(1))
    .join(" ");
}

function defaultActionTitle(action: NotificationActionDefinition): string {
  if (action.title?.trim()) {
    return action.title.trim();
  }

  switch (action.kind) {
    case "open-url":
      return "Open";
    case "run-command":
      return "Run";
    case "reschedule":
      return `Snooze ${action.minutes}m`;
  }
}

function defaultPermissionPrompt(displayName: string): string {
  return `${displayName} needs notification permission so it can show alerts and run the action attached to a notification when you click it.`;
}

function emptyToUndefined(value: string | undefined): string | undefined {
  if (value == null) {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function xmlEscape(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}
