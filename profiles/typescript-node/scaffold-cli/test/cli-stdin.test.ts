import { describe, it, expect } from 'vitest';
import { spawn } from 'node:child_process';
import { once } from 'node:events';

// cli.ts is the I/O shell (coverage-excluded), so its --stdin path is tested at the integration layer:
// spawn the CLI exactly as `npm run dev` does and drive it through real pipes.
function runCli(
  args: string[],
  stdin: string,
  opts: { closeStdout?: boolean } = {},
): Promise<{ code: number | null; stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    const child = spawn('node', ['--import', 'tsx', 'src/cli.ts', ...args], {
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d: Buffer) => (stdout += d.toString()));
    child.stderr.on('data', (d: Buffer) => (stderr += d.toString()));
    child.on('error', reject);
    // Close the read end BEFORE feeding stdin: the child reads stdin, THEN writes stdout — so by the
    // time it writes, the pipe is broken and the write raises EPIPE deterministically.
    if (opts.closeStdout) child.stdout.destroy();
    child.stdin.write(stdin);
    child.stdin.end();
    void once(child, 'close').then(([code]) => resolve({ code: code as number | null, stdout, stderr }));
  });
}

describe('cli --stdin (integration)', () => {
  it('greets a name read from stdin', async () => {
    const { code, stdout } = await runCli(['--stdin'], 'Ada\n');
    expect(stdout).toBe('Hello, Ada!\n');
    expect(code).toBe(0);
  }, 20000);

  it('rejects control-byte input with a nonzero exit (does not pass it through)', async () => {
    const { code, stdout } = await runCli(['--stdin'], 'Ada\x1b[2J\n');
    expect(code).not.toBe(0);
    expect(stdout).toBe(''); // never greeted the tampered input
  }, 20000);

  it('rejects control bytes in --name (nonzero exit, does not echo the payload)', async () => {
    const { code, stdout } = await runCli(['--name', 'X\x1b[2Jcleared'], '');
    expect(code).not.toBe(0);
    expect(stdout).toBe(''); // the ANSI payload is never echoed to output
  }, 20000);

  it('exits cleanly (no uncaught EPIPE) when the downstream reader is closed', async () => {
    const { code, stderr } = await runCli(['--stdin'], 'Ada\n', { closeStdout: true });
    expect(stderr).not.toMatch(/EPIPE/);
    expect(code).toBe(0);
  }, 20000);
});
