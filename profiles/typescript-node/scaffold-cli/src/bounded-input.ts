// bounded-input.ts — a hardened, reusable input boundary for CLI stdin (CP-6).
//
// The Codex-probe throwaway (commitlint-lite) shipped two boundary defects that survived two security
// reviews (docs/architecture/2026-07-11-codex-probe-harvest.md §5): it ACCEPTED terminal-control bytes
// in input, and its `slice(0, n)` SPLIT surrogate pairs into a lone high surrogate. This module is the
// corrected reference an adopter copies: reject control bytes (never strip), and truncate only at a
// code-point boundary so the result is always well-formed.
//
// Split of concerns:
//   • boundAndValidate() — the PURE decision: bound + reject, walked by code point. Fully unit-testable.
//   • readBoundedInput() — the async STREAMING wrapper: drive the source, stop at the cap so an open
//     producer never drains, clean up the iterator, then delegate the decision to boundAndValidate().

/** Thrown when input contains a forbidden terminal-control byte (the "reject, don't strip" contract). */
export class ControlByteError extends Error {
  constructor(
    readonly codePoint: number,
    readonly index: number,
  ) {
    super(
      `forbidden control byte U+${codePoint.toString(16).toUpperCase().padStart(4, '0')} at index ${index}`,
    );
    this.name = 'ControlByteError';
  }
}

/** Thrown when input contains a lone (unpaired) surrogate — malformed UTF-16 (the "reject, don't strip" contract). */
export class MalformedInputError extends Error {
  constructor(
    readonly codePoint: number,
    readonly index: number,
  ) {
    super(
      `lone surrogate U+${codePoint.toString(16).toUpperCase().padStart(4, '0')} at index ${index}`,
    );
    this.name = 'MalformedInputError';
  }
}

export interface BoundOptions {
  /** Maximum retained UTF-16 code units. Truncation never splits a code point, so the cap is a ceiling. */
  maxUnits: number;
}

/** Forbidden = C0 (0x00–0x1F) ∪ C1 (0x80–0x9F) ∪ DEL (0x7F), EXCEPT tab / LF / CR (legitimate whitespace). */
function isForbiddenControl(cp: number): boolean {
  if (cp === 0x09 || cp === 0x0a || cp === 0x0d) return false;
  return cp <= 0x1f || cp === 0x7f || (cp >= 0x80 && cp <= 0x9f);
}

function assertCap(maxUnits: number): void {
  if (!Number.isInteger(maxUnits) || maxUnits < 0) {
    throw new RangeError(`maxUnits must be a non-negative integer, got ${String(maxUnits)}`);
  }
}

/**
 * Bound `input` to at most `maxUnits` UTF-16 units and reject malformed / control input — a single pass
 * BY CODE POINT. Guarantees on the returned string:
 *   - **Well-formed.** Truncation stops before admitting a code point that would exceed the cap, so a
 *     2-unit surrogate pair at the boundary is dropped whole (fixes the `slice(0,n)` split defect); and
 *     a LONE surrogate already in the input is rejected (throws `MalformedInputError`) rather than passed
 *     through — so the result is *always* well-formed, not merely "not newly broken".
 *   - **Control-free.** A forbidden control byte in the admitted region throws `ControlByteError` (fixes
 *     the accept-control-bytes defect). Reject, never strip.
 * A malformed/control byte BEYOND the cap is never admitted, so never judged (it cannot reach output).
 */
export function boundAndValidate(input: string, maxUnits: number): string {
  assertCap(maxUnits);
  let out = '';
  let units = 0;
  for (const ch of input) {
    if (units + ch.length > maxUnits) break; // code-point boundary — never split a pair
    const cp = ch.codePointAt(0)!;
    if (ch.length === 1 && cp >= 0xd800 && cp <= 0xdfff) throw new MalformedInputError(cp, units);
    if (isForbiddenControl(cp)) throw new ControlByteError(cp, units);
    out += ch;
    units += ch.length;
  }
  return out;
}

/**
 * Read at most `maxUnits` UTF-16 units of well-formed, control-byte-free text from an async producer.
 * Stops consuming once `maxUnits` code units are buffered (a producer that keeps yielding non-empty
 * chunks never drains), cleans up the source iterator, then applies the boundary. Rejects (throws
 * ControlByteError / MalformedInputError) on a forbidden or malformed byte.
 *
 * Ceiling: a degenerate producer that yields forever WITHOUT ever emitting a byte (endless empty chunks)
 * and never ends is out of scope — that is indistinguishable from a never-resolving read; real streams
 * (stdin, files) do not behave this way.
 */
export async function readBoundedInput(
  source: AsyncIterable<string>,
  { maxUnits }: BoundOptions,
): Promise<string> {
  assertCap(maxUnits);
  const it = source[Symbol.asyncIterator]();
  let buf = '';
  try {
    while (buf.length < maxUnits) {
      const step = await it.next();
      if (step.done) break;
      buf += step.value;
    }
  } finally {
    await it.return?.();
  }
  return boundAndValidate(buf, maxUnits);
}
