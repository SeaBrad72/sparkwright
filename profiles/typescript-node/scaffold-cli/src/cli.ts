#!/usr/bin/env node
// CLI entrypoint: parse args, call the pure core, print, exit. I/O + process handling lives here and is
// excluded from coverage — the testable logic is the pure greet() and readBoundedInput() functions.
import { greet } from './greet.js';
import { readBoundedInput, boundAndValidate } from './bounded-input.js';

const args = process.argv.slice(2);
if (args.includes('--help') || args.includes('-h')) {
  process.stdout.write('usage: app [--name <name>] [--stdin]\n');
  process.exit(0);
}

async function resolveName(): Promise<string> {
  if (args.includes('--stdin')) {
    // A closed downstream reader (e.g. `app --stdin | head`) must not crash the CLI with EPIPE.
    process.stdout.on('error', (err: NodeJS.ErrnoException) => {
      if (err.code === 'EPIPE') process.exit(0);
      throw err;
    });
    process.stdin.setEncoding('utf8');
    // Bounded, well-formed, control-byte-free read of untrusted stdin. Rejects (throws) on a control
    // byte rather than passing an ANSI/screen-clear payload through to output.
    const raw = await readBoundedInput(process.stdin as unknown as AsyncIterable<string>, {
      maxUnits: 1024,
    });
    return raw.trim();
  }
  // --name is also untrusted (wrapper scripts, CI vars, filename-derived names) — run it through the
  // SAME boundary so an ANSI/screen-clear payload is rejected, not echoed to output.
  const i = args.indexOf('--name');
  const raw = i >= 0 && args[i + 1] !== undefined ? args[i + 1] : '';
  return boundAndValidate(raw, 1024);
}

resolveName()
  .then((name) => {
    process.stdout.write(greet(name) + '\n');
  })
  .catch((err: unknown) => {
    // Set the failure code BEFORE writing, so a security reject is deterministic even if the write races.
    process.exitCode = 1;
    process.stderr.write((err instanceof Error ? err.message : String(err)) + '\n');
  });
