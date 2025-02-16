import { mkdir } from "fs/promises";
import { dirname } from "path";
import { spawn } from "child_process";
import { DownloadItem } from "./db";

export async function downloadFile(
  item: DownloadItem,
  targetDir: string,
): Promise<void> {
  const targetPath = `${targetDir}/${item.filename}`;

  // Ensure target directory exists
  await mkdir(dirname(targetPath), { recursive: true });

  return new Promise((resolve, reject) => {
    // Using -# for the most reliable progress indicator
    const curl = spawn(
      "curl",
      [
        "-L", // Follow redirects
        "-f", // Fail on HTTP errors
        "-o",
        targetPath, // Output file
        item.url, // URL to download
      ],
      {
        stdio: "inherit", // Inherit all stdio to ensure we see everything
      },
    );

    curl.on("close", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`Download failed with code ${code}`));
      }
    });
  });
}
