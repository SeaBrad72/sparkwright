#!/usr/bin/env node
// CLI entrypoint: parse args, call the pure core (greet.ts), print, exit.
// I/O + process handling lives here and is excluded from coverage — the
// testable logic is the pure greet() function in greet.ts.
import { greet } from './greet.js';

const args = process.argv.slice(2);
if (args.includes('--help') || args.includes('-h')) {
  process.stdout.write('usage: app [--name <name>]\n');
  process.exit(0);
}
const i = args.indexOf('--name');
const name = i >= 0 && args[i + 1] !== undefined ? args[i + 1] : '';
process.stdout.write(greet(name) + '\n');
