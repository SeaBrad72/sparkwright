// Pure health-check logic — kept free of I/O so it is trivially unit-testable.
// The HTTP server that exposes this lives in server.ts (excluded from coverage).
export function health(): { status: string } {
  return { status: 'ok' };
}
