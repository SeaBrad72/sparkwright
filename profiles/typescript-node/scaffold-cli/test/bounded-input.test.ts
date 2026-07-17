import { describe, it, expect, vi } from 'vitest';
import {
  readBoundedInput,
  boundAndValidate,
  ControlByteError,
  MalformedInputError,
} from '../src/bounded-input.js';

// ── Hand-built producers. Oracles are constructed independently of the implementation:
//    NO test uses `input.slice(0, n)` (the impl's own expression) as its expected value, and
//    well-formedness is judged by `encodeURIComponent` (throws URIError on a lone surrogate),
//    a mechanism entirely separate from the code-point walk the impl uses.
async function* of(...chunks: string[]): AsyncGenerator<string> {
  for (const c of chunks) yield c;
}
async function* infinite(ch = 'x'): AsyncGenerator<string> {
  for (;;) yield ch;
}
const isWellFormed = (s: string): boolean => {
  try {
    encodeURIComponent(s);
    return true;
  } catch {
    return false;
  }
};

describe('boundAndValidate — bounding + well-formedness (C1)', () => {
  it('returns the input unchanged when it is within the cap', () => {
    expect(boundAndValidate('abc', 10)).toBe('abc');
  });

  it('bounds to exactly maxUnits UTF-16 units for ASCII', () => {
    expect(boundAndValidate('x'.repeat(20), 10)).toBe('x'.repeat(10)); // hand-built oracle
    expect(boundAndValidate('x'.repeat(20), 10)).toHaveLength(10);
  });

  it('truncates at a code-point boundary — never emits a lone surrogate (the slice(0,73) defect)', () => {
    // '😀' is 2 UTF-16 units; admitting it would make 74 > 73, so it is dropped WHOLE.
    const out = boundAndValidate('x'.repeat(72) + '😀', 73);
    expect(isWellFormed(out)).toBe(true);          // independent oracle
    expect(out).toBe('x'.repeat(72));              // hand-built, NOT input.slice(0,73)
    expect(out).toHaveLength(72);
  });

  it('admits a full surrogate pair when it fits exactly at the cap', () => {
    const out = boundAndValidate('x'.repeat(71) + '😀', 73); // 71 + 2 = 73 exactly
    expect(isWellFormed(out)).toBe(true);
    expect(out).toBe('x'.repeat(71) + '😀');
    expect(out).toHaveLength(73);
  });
});

describe('boundAndValidate — control-byte rejection (C2)', () => {
  it('rejects terminal-control payloads (throws ControlByteError, does not strip)', () => {
    expect(() => boundAndValidate('feat: hi\x07\x1b[2Jcleared', 100)).toThrow(ControlByteError);
  });

  it('rejects each forbidden control class (C0, C1, DEL, ESC, BEL, backspace)', () => {
    for (const bad of ['\x00', '\x07', '\x08', '\x1b', '\x7f', '\x9b']) {
      expect(() => boundAndValidate('ok' + bad, 100)).toThrow(ControlByteError);
    }
  });

  it('allows legitimate whitespace \\t \\n \\r', () => {
    expect(boundAndValidate('a\tb\nc\rd', 100)).toBe('a\tb\nc\rd');
  });

  it('ignores a control byte that falls beyond the cap (never admitted, never judged)', () => {
    expect(boundAndValidate('xxxxx\x1b[2Jcleared', 5)).toBe('xxxxx');
  });
});

describe('boundAndValidate — raw lone-surrogate rejection (C1: never emit an ill-formed string)', () => {
  // A lone surrogate ALREADY in the input (not from truncation) must be rejected, not passed through —
  // otherwise the "always well-formed" guarantee is false. Reviewer + Security both caught this.
  it('rejects a raw lone high surrogate', () => {
    expect(() => boundAndValidate('ab\uD800cd', 100)).toThrow(MalformedInputError);
  });
  it('rejects a raw lone low surrogate', () => {
    expect(() => boundAndValidate('ab\uDC00cd', 100)).toThrow(MalformedInputError);
  });
  it('rejects a reversed (low, high) surrogate sequence', () => {
    expect(() => boundAndValidate('\uDC00\uD800', 100)).toThrow(MalformedInputError);
  });
  it('still admits a valid surrogate pair unchanged', () => {
    expect(boundAndValidate('a😀b', 100)).toBe('a😀b');
  });
});

describe('boundAndValidate — maxUnits validation', () => {
  it('throws RangeError on a non-integer maxUnits (NaN would otherwise be unbounded)', () => {
    expect(() => boundAndValidate('x'.repeat(50), Number.NaN)).toThrow(RangeError);
  });
  it('throws RangeError on a negative maxUnits', () => {
    expect(() => boundAndValidate('x', -1)).toThrow(RangeError);
  });
  it('accepts maxUnits 0 (empty result)', () => {
    expect(boundAndValidate('x', 0)).toBe('');
  });
});

describe('readBoundedInput — streaming (C3/C4)', () => {
  it('joins finite input that ends before the cap (EOF < cap)', async () => {
    expect(await readBoundedInput(of('ab', 'cd'), { maxUnits: 10 })).toBe('abcd');
  });

  it('is EOF-independent: a finite producer that ends exactly at the cap returns full content', async () => {
    expect(await readBoundedInput(of('xxx'), { maxUnits: 3 })).toBe('xxx');
  });

  it('returns at the cap from an infinite producer without hanging', async () => {
    expect(await readBoundedInput(infinite('x'), { maxUnits: 5 })).toBe('xxxxx');
  });

  it('cleans up the source iterator (.return called once) when the cap is hit', async () => {
    const ret = vi.fn(async (): Promise<IteratorResult<string>> => ({ done: true, value: undefined }));
    const source: AsyncIterable<string> = {
      [Symbol.asyncIterator]() {
        return {
          next: async (): Promise<IteratorResult<string>> => ({ done: false, value: 'x' }),
          return: ret,
        };
      },
    };
    await readBoundedInput(source, { maxUnits: 3 });
    expect(ret).toHaveBeenCalledTimes(1);
  });

  it('propagates a ControlByteError raised by the streamed content', async () => {
    await expect(readBoundedInput(of('ab\x07cd'), { maxUnits: 100 })).rejects.toThrow(ControlByteError);
  });
});
