import { createWriteStream } from "fs";
import { dirname } from "path";
import { Readable } from "stream";
import { pipeline } from "stream";
import { promisify } from "util";
import { mkdir, writeFile } from "fs/promises";
import fetch from "node-fetch";
import { DownloadItem } from "./db";

const pipelineAsync = promisify(pipeline);

export interface SpeedSample {
  timestamp: number;
  bytes: number;
}

export interface DownloadProgress {
  id: string;
  filename: string;
  url: string;
  bytesDownloaded: number;
  recentSpeed: number; // Last 10s average speed
  averageSpeed: number; // Overall average speed
  startTime: number;
  status: "downloading" | "complete" | "error";
  error?: string;
}

export function calculateSpeed(
  samples: SpeedSample[],
  currentTime: number,
  windowSeconds: number,
): number {
  // Filter samples to the window we care about
  const windowStart = currentTime - windowSeconds * 1000;
  const relevantSamples = samples.filter((s) => s.timestamp >= windowStart);

  if (relevantSamples.length < 2) return 0;

  const first = relevantSamples[0];
  const last = relevantSamples[relevantSamples.length - 1];
  const timeDiff = (last.timestamp - first.timestamp) / 1000; // in seconds
  const bytesDiff = last.bytes - first.bytes;

  return timeDiff > 0 ? bytesDiff / timeDiff : 0;
}

export async function downloadFile(
  item: DownloadItem,
  targetDir: string,
  onProgress?: (progress: DownloadProgress) => void,
): Promise<void> {
  const targetPath = `${targetDir}/${item.filename}`;

  // Ensure target directory exists
  await mkdir(dirname(targetPath), { recursive: true });

  const progress: DownloadProgress = {
    id: item.id,
    filename: item.filename,
    url: item.url,
    bytesDownloaded: 0,
    recentSpeed: 0,
    averageSpeed: 0,
    startTime: Date.now(),
    status: "downloading",
  };

  // Keep last 15 seconds of samples (slightly more than we need to handle edge cases)
  const samples: SpeedSample[] = [];
  const SAMPLE_WINDOW = 15000; // 15 seconds in ms

  try {
    const response = await fetch(item.url);

    if (!response.ok) {
      throw new Error(
        `HTTP error! status: ${response.status} ${response.statusText}`,
      );
    }

    if (!response.body) {
      throw new Error("No response body");
    }

    const body = response.body as unknown as Readable;
    const fileStream = createWriteStream(targetPath);

    // Track progress
    let lastUpdate = Date.now();

    body.on("data", (chunk) => {
      progress.bytesDownloaded += chunk.length;
      const now = Date.now();

      // Add new sample
      samples.push({
        timestamp: now,
        bytes: progress.bytesDownloaded,
      });

      // Remove samples older than our window
      while (samples.length > 0 && samples[0].timestamp < now - SAMPLE_WINDOW) {
        samples.shift();
      }

      if (now - lastUpdate >= 100) {
        // Update every 100ms
        progress.recentSpeed = calculateSpeed(samples, now, 10); // 10 second window
        progress.averageSpeed = calculateSpeed(
          [
            { timestamp: progress.startTime, bytes: 0 },
            { timestamp: now, bytes: progress.bytesDownloaded },
          ],
          now,
          Infinity,
        );

        lastUpdate = now;

        if (onProgress) {
          onProgress(progress);
        }
      }
    });

    await pipelineAsync(body, fileStream);

    const endTime = Date.now();
    progress.status = "complete";
    progress.recentSpeed = progress.averageSpeed = calculateSpeed(
      [
        { timestamp: progress.startTime, bytes: 0 },
        { timestamp: endTime, bytes: progress.bytesDownloaded },
      ],
      endTime,
      Infinity,
    );

    if (onProgress) {
      onProgress(progress);
    }
  } catch (error) {
    progress.status = "error";
    progress.error = error instanceof Error ? error.message : String(error);
    if (onProgress) {
      onProgress(progress);
    }
    throw error;
  }
}
