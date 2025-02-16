import * as fs from "fs";
import * as path from "path";
import { DateTime } from "luxon";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";

interface EmailData {
  content: string;
  fromAddress: string;
  date: string;
}

function convertRfc3339ToMbox(dateStr: string): string {
  try {
    const dt = DateTime.fromRFC2822(dateStr);
    return dt.toFormat("EEE MMM d HH:mm:ss yyyy");
  } catch (error) {
    // Fallback to original date if parsing fails
    console.error(`Failed to parse date: ${dateStr}`);
    return dateStr;
  }
}

function extractHeaderInfo(content: string): EmailData {
  const lines = content.split("\n");
  let fromAddress = "";
  let date = "";

  // Join header lines that are indented (continued headers)
  const joinedLines: string[] = [];
  let currentLine = "";

  for (const line of lines) {
    if (line.match(/^[\t ]/)) {
      currentLine += ` ${line.trim()}`;
    } else {
      if (currentLine) {
        joinedLines.push(currentLine);
      }
      currentLine = line;
    }
  }
  if (currentLine) {
    joinedLines.push(currentLine);
  }

  // Parse headers
  for (const line of joinedLines) {
    if (line === "") break; // End of headers

    if (line.startsWith("From:")) {
      // Extract email address from "From:" header
      const match = line.match(/<(.+@.+)>/) || line.match(/From: (.+@.+)/);
      if (match) {
        fromAddress = match[1];
      }
    } else if (line.startsWith("Date:")) {
      date = line.replace("Date:", "").trim();
      date = convertRfc3339ToMbox(date);
    }
  }

  return {
    content,
    fromAddress,
    date,
  };
}

function convertMaildirToMbox(maildirPath: string, outputFile: string) {
  try {
    const curDir = path.join(maildirPath, "cur");
    const newDir = path.join(maildirPath, "new");

    // Verify directories exist
    if (!fs.existsSync(curDir) || !fs.existsSync(newDir)) {
      throw new Error(
        `Invalid maildir: ${maildirPath} - must contain both 'cur' and 'new' directories`,
      );
    }

    const curFiles = fs.readdirSync(curDir).map((f) => path.join(curDir, f));
    const newFiles = fs.readdirSync(newDir).map((f) => path.join(newDir, f));
    const allFiles = [...curFiles, ...newFiles];
    const total = allFiles.length;
    let count = 0;
    let lastPercent = 0;

    console.error(
      `Starting up, found ${total} emails (${curFiles.length} in cur, ${newFiles.length} in new)`,
    );

    const writeStream = fs.createWriteStream(outputFile);

    for (const filePath of allFiles) {
      // Calculate and show progress
      count++;
      const percent = Math.floor((count * 100) / total);
      if (percent > lastPercent) {
        lastPercent = percent;
        process.stderr.write(`\rConverting: ${percent}% done`);
      }

      const stats = fs.statSync(filePath);

      // Skip directories
      if (!stats.isFile()) continue;

      const content = fs.readFileSync(filePath, "utf-8");
      const emailData = extractHeaderInfo(content);

      // Write in mbox format
      writeStream.write(`From ${emailData.fromAddress}  ${emailData.date}\n`);
      writeStream.write(emailData.content);
      writeStream.write("\n\n");
    }

    writeStream.end();
    console.error("\nFinished.");
  } catch (error) {
    console.error("Error:", error);
    process.exit(1);
  }
}

function convertUserDirToMboxes(userDir: string, outputDir: string) {
  try {
    // Ensure output directory exists
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }

    const entries = fs.readdirSync(userDir, { withFileTypes: true });
    const userDirs = entries.filter((entry) => entry.isDirectory());

    console.error(`Found ${userDirs.length} user directories to process`);

    for (const userDir of userDirs) {
      const userName = userDir.name;
      const userPath = path.join(userDir.path, userName);
      const outputFile = path.join(outputDir, `${userName}.mbox`);

      console.error(`\nProcessing user: ${userName}`);
      try {
        convertMaildirToMbox(userPath, outputFile);
      } catch (error) {
        console.error(`Error processing ${userName}: ${error}`);
      }
    }

    console.error("\nAll user directories processed.");
  } catch (error) {
    console.error("Error:", error);
    process.exit(1);
  }
}

// Parse command line arguments using yargs
void (async () => {
  await yargs(hideBin(process.argv))
    .command(
      "single",
      "Convert a single maildir to mbox format",
      (yargs) => {
        return yargs
          .option("maildir", {
            alias: "m",
            type: "string",
            description:
              "Input maildir path containing 'cur' and 'new' directories",
            demandOption: true,
          })
          .option("output", {
            alias: "o",
            type: "string",
            description: "Output mbox file path",
            demandOption: true,
          });
      },
      (argv) => {
        convertMaildirToMbox(argv.maildir, argv.output);
      },
    )
    .command(
      "userdir",
      "Convert all maildirs under a user directory to mbox format",
      (yargs) => {
        return yargs
          .option("maildir", {
            alias: "m",
            type: "string",
            description: "User directory containing multiple maildir folders",
            demandOption: true,
          })
          .option("output-dir", {
            alias: "o",
            type: "string",
            description: "Output directory for mbox files",
            demandOption: true,
          });
      },
      (argv) => {
        convertUserDirToMboxes(argv.maildir, argv["output-dir"]);
      },
    )
    .demandCommand(1, "You must specify a command")
    .help().argv;
})();
