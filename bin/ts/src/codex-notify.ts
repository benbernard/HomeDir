#!/usr/bin/env tsx

import yargs from "yargs";
import { hideBin } from "yargs/helpers";
import {
  buildCodexNotification,
  parseCodexNotifyPayload,
} from "./lib/codex-notify";
import {
  buildNotificationApp,
  getDefaultNotificationAppDir,
  getNotificationsManifestPath,
  loadNotificationsManifest,
  needsRebuild,
  resolveNotificationRequest,
  resolveProfilePaths,
  sendNotificationAppRequest,
} from "./lib/notifications";

type CommonArgs = {
  appDir?: string;
  homeDir?: string;
  manifestPath?: string;
  profile: string;
};

async function main() {
  const argv = await yargs(hideBin(process.argv))
    .scriptName("codex-notify")
    .strict()
    .help()
    .usage("$0 <payload-json>")
    .positional("payload-json", {
      describe: "JSON payload passed by Codex via the notify config setting",
      type: "string",
    })
    .option("home-dir", {
      type: "string",
      description: "Override the home directory used to locate notifications/",
      hidden: true,
    })
    .option("manifest-path", {
      type: "string",
      description: "Override the notifications manifest path",
      hidden: true,
    })
    .option("app-dir", {
      type: "string",
      description: "Override the output directory for built notifier apps",
      hidden: true,
    })
    .option("profile", {
      type: "string",
      default: "codex",
      description: "Notification profile name from notifications/manifest.json",
    })
    .demandCommand(1)
    .parse();

  const args = argv as typeof argv & CommonArgs;
  const rawPayload = args._[0];
  if (typeof rawPayload !== "string" || rawPayload.trim().length === 0) {
    throw new Error(
      "Expected Codex to pass a notification payload as the first argument.",
    );
  }

  const payload = parseCodexNotifyPayload(rawPayload);
  const content = buildCodexNotification(payload);
  const manifestPath =
    args.manifestPath ?? getNotificationsManifestPath(args.homeDir);
  const manifest = loadNotificationsManifest(manifestPath);
  const profile = manifest.profiles[args.profile];

  if (!profile) {
    throw new Error(
      `Profile "${args.profile}" was not found in notifications/manifest.json.`,
    );
  }

  const appDir = args.appDir ?? getDefaultNotificationAppDir(args.homeDir);
  const paths = resolveProfilePaths({
    appDir,
    homeDir: args.homeDir,
    manifestPath,
    profile,
  });

  if (needsRebuild(paths)) {
    buildNotificationApp({
      appDir,
      homeDir: args.homeDir,
      manifestPath,
      profile,
      profileName: args.profile,
    });
  }

  const request = resolveNotificationRequest({
    body: content.body,
    context: content.context,
    profile,
    profileName: args.profile,
    subtitle: content.subtitle,
    title: content.title,
  });

  sendNotificationAppRequest(paths, request);
}

await main().catch((error) => {
  const detail = error instanceof Error ? error.message : String(error);
  console.error(detail);
  process.exit(1);
});
