#!/usr/bin/env tsx

import { createReadStream } from "fs";
import { basename } from "path";
import { createInterface } from "readline";
import {
  HeadBucketCommand,
  HeadObjectCommand,
  S3Client,
  S3ServiceException,
} from "@aws-sdk/client-s3";
import { fromIni } from "@aws-sdk/credential-provider-ini";
import { Upload } from "@aws-sdk/lib-storage";
import chalk from "chalk";
import { lookup } from "mime-types";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";
import { logError, logInfo, logSuccess, logWarning } from "./lib/logger";
import { promptYesNo } from "./lib/prompts";

interface UploadOptions {
  file?: string;
  name?: string;
  upload?: string;
  bucket: string;
  prompt: boolean;
  profile: string;
  region: string;
  yes: boolean;
  _: string[];
}

async function testBucketAccess(client: S3Client, bucket: string) {
  try {
    await client.send(new HeadBucketCommand({ Bucket: bucket }));
  } catch (error) {
    logError(
      `Failed to access bucket ${chalk.bold(
        bucket,
      )}. Please check your AWS credentials and bucket permissions.`,
      error,
    );
    process.exit(1);
  }
}

async function promptForName(
  defaultName: string,
  file: string,
): Promise<string> {
  const extension = file.match(/(\..*)$/)?.[1] || ".txt";

  const rl = createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  console.log(
    `\nUpload name ${chalk.gray(
      `(will add ${extension} unless an extension is specified)`,
    )}`,
  );
  console.log(chalk.gray(`Default: ${defaultName}`));
  const input = await new Promise<string>((resolve) => {
    rl.question(chalk.blue("Name: "), resolve);
  });
  rl.close();

  let uploadName = input.trim() || defaultName;
  if (!uploadName.includes(".")) {
    uploadName += extension;
  }

  return uploadName;
}

async function checkFileExists(
  client: S3Client,
  bucket: string,
  key: string,
): Promise<boolean> {
  try {
    await client.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
    return true;
  } catch (error) {
    // If the error is NoSuchKey, the file doesn't exist
    if (error instanceof S3ServiceException && error.name === "NotFound") {
      return false;
    }
    // For other errors, we should throw
    throw error;
  }
}

async function main() {
  const argv = (await yargs(hideBin(process.argv))
    .option("file", { type: "string", description: "File to upload" })
    .option("name", {
      type: "string",
      description: "Resulting name (defaults to --file)",
    })
    .option("upload", { type: "string", description: "Same as --name" })
    .option("bucket", {
      type: "string",
      default: "bernard-public",
      description: "Bucket to upload to",
    })
    .option("prompt", {
      type: "boolean",
      default: false,
      description: "Prompt for upload name",
    })
    .option("profile", {
      type: "string",
      default: "personal",
      description: "AWS profile to use for authentication",
    })
    .option("region", {
      type: "string",
      default: "us-east-1",
      description: "AWS region for the S3 bucket",
    })
    .option("yes", {
      type: "boolean",
      alias: "y",
      default: false,
      description: "Automatically answer yes to prompts",
    })
    .help()
    .example("$0 mypic.jpg", "Upload a picture")
    .example(
      "$0 data.csv --name saved-data-for-bob.csv",
      "Upload a .csv, changing the name",
    ).argv) as UploadOptions;

  let file = argv.file;
  if (!file && argv._.length > 0) {
    if (argv._.length > 1) {
      console.error(
        "Found extra arguments, can only upload one file at a time!",
      );
      process.exit(1);
    }
    file = argv._[0];
  }

  if (!file) {
    console.error("Must specify a file to upload");
    process.exit(1);
  }

  let uploadName = argv.name || argv.upload;
  if (argv.prompt && !uploadName) {
    const defaultName = basename(file);
    uploadName = await promptForName(defaultName, file);
  }

  uploadName = uploadName || basename(file);

  const client = new S3Client({
    credentials: fromIni({ profile: argv.profile }),
    region: argv.region,
  });

  console.log(`\n${chalk.blue.bold("AWS Configuration")}`);
  logInfo(
    `Using profile ${chalk.bold(argv.profile)} in region ${chalk.bold(
      argv.region,
    )}`,
  );
  await testBucketAccess(client, argv.bucket);

  // Check if file exists
  const fileExists = await checkFileExists(client, argv.bucket, uploadName);
  if (fileExists && !argv.yes) {
    const shouldOverwrite = await promptYesNo(
      `File ${chalk.bold(uploadName)} already exists in bucket ${chalk.bold(
        argv.bucket,
      )}. Overwrite?`,
    );
    if (!shouldOverwrite) {
      logWarning("Upload cancelled");
      process.exit(0);
    }
  }

  console.log(`\n${chalk.blue.bold("Upload Details")}`);
  logInfo(`Source file: ${chalk.bold(file)}`);
  logInfo(`Target name: ${chalk.bold(uploadName)}`);

  try {
    const contentType = lookup(uploadName) || "application/octet-stream";
    logInfo(`Content-Type: ${chalk.bold(contentType)}`);

    const upload = new Upload({
      client,
      params: {
        Bucket: argv.bucket,
        Key: uploadName,
        Body: createReadStream(file),
        ACL: "public-read",
        ContentType: contentType,
        ContentDisposition: "inline",
        ...(contentType.startsWith("text/") || contentType === "image/svg+xml"
          ? { ContentType: `${contentType}; charset=utf-8` }
          : {}),
      },
    });

    await upload.done();

    console.log(`\n${chalk.green.bold("Upload Complete")}`);
    logSuccess(`File uploaded successfully to ${chalk.bold(argv.bucket)}`);
    console.log(`\n${chalk.blue.bold("Access URLs")}`);
    console.log(
      `${chalk.gray("→ ")}https://s3.amazonaws.com/${
        argv.bucket
      }/${uploadName}`,
    );
    console.log(
      `${chalk.gray("→ ")}https://${
        argv.bucket
      }.s3.amazonaws.com/${uploadName}`,
    );
    console.log(); // Add a newline at the end
  } catch (error) {
    logError("Upload failed", error);
    process.exit(1);
  }
}

main().catch((error) => {
  logError("Unexpected error occurred", error);
  process.exit(1);
});
