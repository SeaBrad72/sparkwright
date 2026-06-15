# Your First Feature — the TDD rhythm (worked)

This zooms into the **Build** step of [WALKTHROUGH.md](../../WALKTHROUGH.md) and shows the
red-green-refactor rhythm with real code. **Illustrative — shown in the reference stack
(TypeScript/Node); your `profiles/<stack>.md` has the exact commands for yours.**

The discipline is always the same three beats:

## 1. RED — write the failing test first

```ts
// src/cart.test.ts
import { describe, it, expect } from "vitest";
import { subtotal } from "./cart";

it("sums line items", () => {
  expect(subtotal([{ price: 300, qty: 2 }, { price: 150, qty: 1 }])).toBe(750);
});
```

Run it. It MUST fail (the function doesn't exist yet):

```
$ npm test
✗ subtotal is not defined
```

Why first? The failing test proves the test actually tests something — and pins down the behaviour
*before* you write code to fit it.

## 2. GREEN — the minimal code to pass

```ts
// src/cart.ts
type Line = { price: number; qty: number };
export const subtotal = (lines: Line[]): number =>
  lines.reduce((sum, l) => sum + l.price * l.qty, 0);
```

```
$ npm test
✓ sums line items
```

Minimal. No edge cases you don't have a test for yet (YAGNI).

## 3. REFACTOR — improve with the test as your net

Now make it clean/safe knowing the test will catch a regression — e.g. guard against an empty cart,
add a test for it first (back to RED), then refactor. The test suite is what lets you change code
*without fear* — that safety net is the whole point, and it's why the kit treats tests as
non-negotiable rather than optional.

## What just happened (the enterprise part)

That rhythm is one beat inside the larger loop in [WALKTHROUGH.md](../../WALKTHROUGH.md): your tests
become the CI gate, the gate guards every future change, and the agent can move at machine speed
between the human checkpoints *because* the tests exist. Coding was the task; the test, the gate,
and the loop around it are the engineering.
