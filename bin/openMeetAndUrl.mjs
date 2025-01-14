#!/usr/local/bin/node

import { spawnSync } from "node:child_process";

const DEBUG = false;

function openGoogleMeet() {
	const command = "open";
	const args = [
		"-a",
		"/Users/benbernard/Applications/Chrome Apps.localized/Google Meet.app",
	];

	if (DEBUG) {
		console.log(`Running ${command} ${args.join(" ")}`);
	}

	spawnSync(command, args, { stdio: "inherit" });
	spawnSync("sleep", [2], { stdio: "inherit" });
}

function openUrl(url) {
	const command =
		"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
	const args = ["-g", "--args", "--profile-directory=Default", url];

	if (DEBUG) {
		console.log(`Running ${command} ${args.join(" ")}`);
	}

	spawnSync(command, args, { stdio: "inherit" });
}

// Find if the Google Meet.app is running
function isGoogleMeetRunning() {
	const command = "ps";
	const args = ["-ax", "-o", "command"];

	if (DEBUG) {
		console.log(`Running ${command} ${args.join(" ")}`);
	}

	const result = spawnSync(command, args, { stdio: "pipe" });
	const output = result.stdout.toString();

	if (DEBUG) {
		console.log(`Output: ${output}`);
	}

	return output.includes("Google Meet.app/Contents/MacOS/app_mode_loader");
}

function main() {
	if (!isGoogleMeetRunning()) {
		openGoogleMeet();
	}

	if (process.argv.length < 3) {
		console.log("Usage: openMeetAndUrl <url>");
		process.exit(1);
	}

	openUrl(process.argv[2]);
}

main();
