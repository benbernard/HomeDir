#!/usr/bin/env tsx

import { mkdirSync } from "fs";
import { dirname } from "path";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";
import {
  buildNotificationApp,
  createProfileTemplate,
  getDefaultNotificationAppDir,
  getNotificationsManifestPath,
  loadNotificationsManifest,
  needsRebuild,
  parseKeyValuePairs,
  resolveNotificationRequest,
  resolveProfilePaths,
  saveNotificationsManifest,
  sendNotificationAppRequest,
  validateProfile,
} from "./lib/notifications";

type CommonArgs = {
  appDir?: string;
  homeDir?: string;
  manifestPath?: string;
};

type BuilderArgv<T> = T & CommonArgs;

function resolveManifestPathFromArgs(argv: CommonArgs): string {
  return argv.manifestPath ?? getNotificationsManifestPath(argv.homeDir);
}

function resolveAppDirFromArgs(argv: CommonArgs): string {
  return argv.appDir ?? getDefaultNotificationAppDir(argv.homeDir);
}

function loadManifestOrThrow(argv: CommonArgs) {
  const manifestPath = resolveManifestPathFromArgs(argv);
  return {
    manifest: loadNotificationsManifest(manifestPath),
    manifestPath,
  };
}

function requireProfile(
  profileName: string,
  profiles: Record<string, ReturnType<typeof createProfileTemplate>>,
) {
  const profile = profiles[profileName];
  if (!profile) {
    throw new Error(
      `Profile "${profileName}" was not found in notifications/manifest.json.`,
    );
  }
  return profile;
}

function printValidation(profileName: string, errors: string[]) {
  if (errors.length === 0) {
    console.log(`- ${profileName}: valid`);
    return;
  }

  console.log(`- ${profileName}: invalid`);
  for (const error of errors) {
    console.log(`    ${error}`);
  }
}

await yargs(hideBin(process.argv))
  .scriptName("notifyctl")
  .strict()
  .help()
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
  .command("list", "List configured notification app profiles", {}, (argv) => {
    const args = argv as unknown as CommonArgs;
    const { manifest } = loadManifestOrThrow(args);
    console.log(`Apps install into ${resolveAppDirFromArgs(args)} by default.`);
    for (const [profileName, profile] of Object.entries(manifest.profiles)) {
      printValidation(profileName, validateProfile(profileName, profile));
    }
  })
  .command(
    "new <profile>",
    "Create a new notification app profile scaffold",
    {
      "bundle-id": {
        type: "string",
        description: "Bundle ID for the generated app",
      },
      "display-name": {
        type: "string",
        description: "Human-readable app name",
      },
      icon: {
        type: "string",
        description: "Relative or absolute .icns path",
      },
      "permission-prompt": {
        type: "string",
        description:
          "User-facing copy shown before the app requests notification permission",
      },
      sound: {
        type: "string",
        description: "Notification sound name",
        default: "default",
      },
    },
    (argv) => {
      const args = argv as unknown as BuilderArgv<{
        bundleId?: string;
        displayName?: string;
        icon?: string;
        permissionPrompt?: string;
        profile: string;
        sound: string;
      }>;
      const manifestPath = resolveManifestPathFromArgs(args);
      const manifest = (() => {
        try {
          return loadNotificationsManifest(manifestPath);
        } catch {
          return {
            $schemaVersion: 1,
            profiles: {},
          };
        }
      })();

      if (manifest.profiles[args.profile]) {
        throw new Error(`Profile "${args.profile}" already exists.`);
      }

      manifest.profiles[args.profile] = createProfileTemplate(args.profile, {
        bundleId: args.bundleId,
        displayName: args.displayName,
        icon: args.icon,
        permissionPrompt: args.permissionPrompt,
        sound: args.sound,
      });

      saveNotificationsManifest(manifest, manifestPath);

      const iconPath = resolveProfilePaths({
        appDir: resolveAppDirFromArgs(args),
        homeDir: args.homeDir,
        manifestPath,
        profile: manifest.profiles[args.profile],
      }).iconSourcePath;
      mkdirSync(dirname(iconPath), { recursive: true });

      console.log(`Added profile "${args.profile}" to ${manifestPath}`);
      console.log(`Next: place a .icns file at ${iconPath}`);
    },
  )
  .command(
    "build [profile]",
    "Build one notification app or all profiles",
    {},
    (argv) => {
      const args = argv as unknown as BuilderArgv<{ profile?: string }>;
      const { manifest, manifestPath } = loadManifestOrThrow(args);
      const appDir = resolveAppDirFromArgs(args);
      const selectedProfiles: [
        string,
        ReturnType<typeof createProfileTemplate>,
      ][] = args.profile
        ? [[args.profile, requireProfile(args.profile, manifest.profiles)]]
        : Object.entries(manifest.profiles);

      for (const [profileName, profile] of selectedProfiles) {
        const errors = validateProfile(profileName, profile);
        if (errors.length > 0) {
          throw new Error(errors.join("\n"));
        }

        const paths = buildNotificationApp({
          appDir,
          homeDir: args.homeDir,
          manifestPath,
          profile,
          profileName,
        });
        console.log(`Built ${profile.displayName}: ${paths.bundleDir}`);
      }
    },
  )
  .command(
    "send <profile>",
    "Send a notification through a built app profile",
    {
      actions: {
        type: "boolean",
        default: true,
        description: "Include the profile's custom button actions",
      },
      data: {
        array: true,
        type: "string",
        description: "Template values in key=value form",
        default: [],
      },
      "default-action": {
        type: "boolean",
        default: true,
        description: "Include the profile's default click action",
      },
      message: {
        alias: "body",
        type: "string",
        description: "Notification body",
        default: "",
      },
      "notification-id": {
        type: "string",
        description: "Override the generated notification identifier",
      },
      sound: {
        type: "string",
        description: "Override the profile sound",
      },
      subtitle: {
        type: "string",
        description: "Notification subtitle",
      },
      title: {
        type: "string",
        demandOption: true,
        description: "Notification title",
      },
    },
    (argv) => {
      const args = argv as unknown as BuilderArgv<{
        actions: boolean;
        data: string[];
        defaultAction: boolean;
        message: string;
        notificationId?: string;
        profile: string;
        sound?: string;
        subtitle?: string;
        title: string;
      }>;
      const { manifest, manifestPath } = loadManifestOrThrow(args);
      const profile = requireProfile(args.profile, manifest.profiles);
      const appDir = resolveAppDirFromArgs(args);
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

      const effectiveProfile = {
        ...profile,
        actions: args.actions ? profile.actions : [],
        defaultAction: args.defaultAction ? profile.defaultAction : undefined,
      };

      const request = resolveNotificationRequest({
        body: args.message,
        context: parseKeyValuePairs(args.data),
        notificationId: args.notificationId,
        profile: effectiveProfile,
        profileName: args.profile,
        sound: args.sound,
        subtitle: args.subtitle,
        title: args.title,
      });
      sendNotificationAppRequest(paths, request);
    },
  )
  .demandCommand(1)
  .parseAsync();
