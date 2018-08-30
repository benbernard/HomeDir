#!/usr/bin/env node
var readline = require('readline');

var rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
  terminal: false
});

let lines = [];
rl.on('line', function (line) {
  lines.push(line);
});

rl.on('close', function () {
  let items = lines.map(line => ({
    uid: line,
    title: line,
    arg: line,
    autocomplete: line,
  }))

  console.log(JSON.stringify({items}));
})
