import chalk from "chalk";

export function logError(message: string, details?: unknown): void {
  console.error(`${chalk.red("Error:")} ${message}`);
  if (details) console.error(chalk.gray(String(details)));
}

export function logInfo(message: string): void {
  console.log(`${chalk.blue("→")} ${message}`);
}

export function logSuccess(message: string): void {
  console.log(`${chalk.green("✓")} ${message}`);
}

export function logWarning(message: string): void {
  console.log(`${chalk.yellow("!")} ${message}`);
}

export function logDebug(message: string, verbose: boolean): void {
  if (verbose) {
    console.log(`${chalk.gray("DEBUG:")} ${message}`);
  }
}
