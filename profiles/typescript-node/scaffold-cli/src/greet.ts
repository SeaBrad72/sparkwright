// Pure greeting logic — kept free of I/O so it is trivially unit-testable.
// The CLI that parses argv and prints lives in cli.ts (excluded from coverage).
export function greet(name: string): string {
  const who = name.trim() === '' ? 'world' : name.trim();
  return `Hello, ${who}!`;
}
