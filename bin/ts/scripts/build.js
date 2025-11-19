#!/usr/bin/env node

const { build } = require('esbuild');
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

if (isWatch) {
  buildOptions.watch = {
    onRebuild(error) {
      if (error) {
        console.error('Watch build failed:', error);
      } else {
        removeExtensionsAndMakeExecutable();
        console.log('Rebuild complete');
      }
    },
  };
}

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

build(buildOptions)
  .then(() => {
    removeExtensionsAndMakeExecutable();
    console.log(isWatch ? 'Watching for changes...' : 'Build complete');
    if (!isWatch) process.exit(0);
  })
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
