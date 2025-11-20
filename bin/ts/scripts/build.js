#!/usr/bin/env node

const { context, build } = require('esbuild');
const { readdirSync, renameSync, chmodSync } = require('fs');
const { join } = require('path');

const srcDir = join(__dirname, '../src');
const distDir = join(__dirname, '../dist');

// Get all .ts files in src directory
const entryPoints = readdirSync(srcDir)
  .filter(file => file.endsWith('.ts'))
  .map(file => join(srcDir, file));

const isWatch = process.argv.includes('--watch');

const buildOptions = {
  entryPoints,
  bundle: false,
  platform: 'node',
  target: 'node18',
  outdir: distDir,
  format: 'cjs',
};

function removeExtensionsAndMakeExecutable() {
  const files = readdirSync(distDir);
  for (const file of files) {
    if (file.endsWith('.js')) {
      const oldPath = join(distDir, file);
      const newPath = join(distDir, file.replace(/\.js$/, ''));
      renameSync(oldPath, newPath);
      chmodSync(newPath, 0o755);
    }
  }
}

async function main() {
  if (isWatch) {
    const ctx = await context(buildOptions);

    // Do initial build
    await ctx.rebuild();
    removeExtensionsAndMakeExecutable();
    console.log('Initial build complete. Watching for changes...');

    // Start watching
    await ctx.watch();

    // Watch for changes and process
    const chokidar = require('chokidar');
    chokidar.watch(distDir + '/*.js').on('add', () => {
      setTimeout(() => {
        try {
          removeExtensionsAndMakeExecutable();
          console.log('Rebuild complete');
        } catch (err) {
          // Ignore errors during processing
        }
      }, 100);
    });
  } else {
    await build(buildOptions);
    removeExtensionsAndMakeExecutable();
    console.log('Build complete');
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
