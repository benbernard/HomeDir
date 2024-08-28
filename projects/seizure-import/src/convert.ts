#!npx tsx

import fs from "node:fs";
import path from "node:path";
import * as csvWriter from "csv-writer";

const directoryPath = "data/medical-kat";
const outputFilePath = "output.csv";

try {
	const files = fs.readdirSync(directoryPath);
	console.log("Files in data/medical-kat:");
	for (const file of files) {
		console.log(file);
		const filePath = path.join(directoryPath, file);
		const data = JSON.parse(fs.readFileSync(filePath, "utf-8"));
		const records: {
			time: string;
			duration: string;
			notes: string;
			link: string;
		}[] = [];

		for (const message of data) {
			const text = message.text;
			const matches = text.match(/\b\d+s\b/g);
			if (matches) {
				for (const match of matches) {
					const duration = match.replace("s", "");
					const time = new Date(
						Number.parseFloat(message.ts) * 1000,
					).toLocaleString("en-US", {
						timeZone: "America/Los_Angeles",
						year: "numeric",
						month: "2-digit",
						day: "2-digit",
						hour: "2-digit",
						minute: "2-digit",
						hour12: false,
					});
					const link = `https://slack.com/archives/${message.channel_id}/p${message.ts.replace(".", "")}`;
					const formattedTime = `${time.slice(0, 10)} ${time.slice(11, 17)}`;
					records.push({
						time: formattedTime,
						duration,
						notes: `Slack: ${text}`,
						link,
					});
				}
			}
		}

		const createCsvWriter = csvWriter.createObjectCsvWriter;
		const writer = createCsvWriter({
			path: outputFilePath,
			header: [
				{ id: "time", title: "time" },
				{ id: "duration", title: "duration" },
				{ id: "notes", title: "notes" },
				{ id: "link", title: "link" },
			],
			append: true,
		});

		writer
			.writeRecords(records)
			.then(() =>
				console.log(`The CSV file was written successfully for ${file}`),
			);
	}
} catch (err) {
	console.error("Error reading directory:", err);
}
