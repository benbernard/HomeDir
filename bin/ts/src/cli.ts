#!/usr/bin/env node

import yargs from "yargs";
import { hideBin } from "yargs/helpers";

yargs(hideBin(process.argv))
  .command(
    "list",
    "List available items",
    (yargs) => {
      return yargs;
    },
    async (argv) => {
      console.log("List command executed");
    },
  )
  .command(
    "download",
    "Download an item",
    (yargs) => {
      return yargs.option("name", {
        alias: "n",
        type: "string",
        description: "Name of the item to download",
        demandOption: true,
      });
    },
    async (argv) => {
      console.log(`Download command executed for: ${argv.name}`);
    },
  )
  .command(
    "add",
    "Add a new item",
    (yargs) => {
      return yargs
        .option("name", {
          alias: "n",
          type: "string",
          description: "Name of the item",
          demandOption: true,
        })
        .option("path", {
          alias: "p",
          type: "string",
          description: "Path to the item",
          demandOption: true,
        });
    },
    async (argv) => {
      console.log(
        `Add command executed for: ${argv.name} at path: ${argv.path}`,
      );
    },
  )
  .demandCommand(1, "You must specify a command")
  .strict()
  .help().argv;
