import { describe, it, expect } from 'vitest';
import { greet } from '../src/greet.js';

describe('greet', () => {
  it('greets a given name', () => {
    expect(greet('Ada')).toBe('Hello, Ada!');
  });
  it('defaults to world when empty or whitespace', () => {
    expect(greet('')).toBe('Hello, world!');
    expect(greet('   ')).toBe('Hello, world!');
  });
  it('trims surrounding whitespace', () => {
    expect(greet('  Ada  ')).toBe('Hello, Ada!');
  });
});
