import { describe, expect, it } from "vitest";
import { type SpeedSample, calculateSpeed } from "./download";

describe("download - Speed Calculation", () => {
  it("should return 0 for less than 2 samples", () => {
    expect(calculateSpeed([], 1000, 10)).toBe(0);
    expect(calculateSpeed([{ timestamp: 1000, bytes: 100 }], 1000, 10)).toBe(0);
  });

  it("should calculate speed correctly for 2 samples", () => {
    const samples: SpeedSample[] = [
      { timestamp: 1000, bytes: 0 },
      { timestamp: 2000, bytes: 1000 }, // 1000 bytes in 1 second
    ];
    const speed = calculateSpeed(samples, 2000, 10);
    expect(speed).toBe(1000); // 1000 bytes/second
  });

  it("should calculate speed over multiple samples", () => {
    const samples: SpeedSample[] = [
      { timestamp: 1000, bytes: 0 },
      { timestamp: 2000, bytes: 1000 },
      { timestamp: 3000, bytes: 3000 }, // 3000 bytes over 2 seconds = 1500 bytes/sec
    ];
    const speed = calculateSpeed(samples, 3000, 10);
    expect(speed).toBe(1500);
  });

  it("should filter samples outside the time window", () => {
    const samples: SpeedSample[] = [
      { timestamp: 1000, bytes: 0 }, // Outside 10s window from time 20000
      { timestamp: 11000, bytes: 5000 }, // Just inside window
      { timestamp: 20000, bytes: 15000 }, // Current time
    ];
    const speed = calculateSpeed(samples, 20000, 10);
    // Only considers samples from 11000 and 20000
    // 15000 - 5000 = 10000 bytes over 9 seconds = ~1111 bytes/sec
    expect(speed).toBeCloseTo(1111.11, 1);
  });

  it("should return 0 when time difference is 0", () => {
    const samples: SpeedSample[] = [
      { timestamp: 1000, bytes: 0 },
      { timestamp: 1000, bytes: 100 }, // Same timestamp
    ];
    const speed = calculateSpeed(samples, 1000, 10);
    expect(speed).toBe(0);
  });

  it("should handle window larger than available data", () => {
    const samples: SpeedSample[] = [
      { timestamp: 1000, bytes: 0 },
      { timestamp: 2000, bytes: 2000 },
    ];
    // Window is 100 seconds, but data is only 1 second
    const speed = calculateSpeed(samples, 2000, 100);
    expect(speed).toBe(2000); // Still calculates correctly with available data
  });

  it("should handle real-world scenario with multiple samples", () => {
    // Simulating download at ~100 KB/s
    const samples: SpeedSample[] = [
      { timestamp: 0, bytes: 0 },
      { timestamp: 1000, bytes: 100000 },
      { timestamp: 2000, bytes: 200000 },
      { timestamp: 3000, bytes: 300000 },
      { timestamp: 4000, bytes: 400000 },
    ];
    const speed = calculateSpeed(samples, 4000, 10);
    expect(speed).toBe(100000); // 100 KB/s
  });

  it("should handle irregular sample intervals", () => {
    const samples: SpeedSample[] = [
      { timestamp: 1000, bytes: 0 },
      { timestamp: 1500, bytes: 500 }, // 0.5s
      { timestamp: 3000, bytes: 2000 }, // 1.5s gap
      { timestamp: 3100, bytes: 2100 }, // 0.1s
    ];
    const speed = calculateSpeed(samples, 3100, 10);
    // 2100 bytes over 2.1 seconds = 1000 bytes/sec
    expect(speed).toBe(1000);
  });

  it("should filter correctly with exact window boundary", () => {
    const currentTime = 10000;
    const windowSeconds = 5;
    const samples: SpeedSample[] = [
      { timestamp: 4999, bytes: 0 }, // Just outside window (10000 - 5*1000 = 5000)
      { timestamp: 5000, bytes: 1000 }, // Exactly at window start
      { timestamp: 10000, bytes: 6000 }, // Current time
    ];
    const speed = calculateSpeed(samples, currentTime, windowSeconds);
    // Should include samples from 5000 onwards
    // 6000 - 1000 = 5000 bytes over 5 seconds = 1000 bytes/sec
    expect(speed).toBe(1000);
  });

  it("should handle Infinity window (overall average)", () => {
    const samples: SpeedSample[] = [
      { timestamp: 0, bytes: 0 },
      { timestamp: 10000, bytes: 50000 },
    ];
    const speed = calculateSpeed(samples, 10000, Infinity);
    expect(speed).toBe(5000); // 50000 bytes over 10 seconds
  });
});
