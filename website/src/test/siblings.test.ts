import { describe, it, expect } from 'vitest'
import { rotatingSiblings } from '../lib/siblings'
import { competitors } from '../data/competitors'
import { whatToDoPages } from '../data/whatToDo'

/**
 * Guards US-SEO010 — even internal-link distribution.
 *
 * The property that matters is not "each page shows three links", it is "every
 * page RECEIVES the same number". A slice(0, 3) satisfies the first and fails
 * the second, which is how six of ten comparison pages ended up with a single
 * inbound link while three absorbed the rest.
 */

const SIBLING_COUNT = 3

/** How many sibling blocks each index appears in, across the whole set. */
function inboundCounts(size: number, count: number): number[] {
  const inbound = new Array<number>(size).fill(0)
  for (let i = 0; i < size; i++) {
    for (const j of rotatingSiblings([...Array(size).keys()], i, count)) inbound[j]++
  }
  return inbound
}

describe('rotatingSiblings', () => {
  it('never includes the page itself', () => {
    for (let i = 0; i < 10; i++) {
      expect(rotatingSiblings([...Array(10).keys()], i, 3)).not.toContain(i)
    }
  })

  it('gives every page exactly the same number of inbound links', () => {
    for (const size of [4, 6, 10, 12]) {
      expect(new Set(inboundCounts(size, SIBLING_COUNT))).toEqual(new Set([SIBLING_COUNT]))
    }
  })

  it('is what the old slice(0, 3) was not', () => {
    // The regression, stated as the bug it replaces.
    const size = 10
    const sliced = new Array<number>(size).fill(0)
    for (let i = 0; i < size; i++) {
      for (const j of [...Array(size).keys()].filter((j) => j !== i).slice(0, 3)) sliced[j]++
    }
    expect(Math.min(...sliced)).toBe(0)
    expect(Math.max(...inboundCounts(size, SIBLING_COUNT))).toBe(SIBLING_COUNT)
    expect(Math.min(...inboundCounts(size, SIBLING_COUNT))).toBe(SIBLING_COUNT)
  })

  it('degrades safely on small or invalid input', () => {
    expect(rotatingSiblings([], 0, 3)).toEqual([])
    expect(rotatingSiblings(['a'], 0, 3)).toEqual([])
    expect(rotatingSiblings(['a', 'b'], 0, 3)).toEqual(['b'])
    expect(rotatingSiblings(['a', 'b', 'c'], -1, 3)).toEqual([])
    expect(rotatingSiblings(['a', 'b', 'c'], 99, 3)).toEqual([])
    expect(rotatingSiblings(['a', 'b', 'c'], 0, 0)).toEqual([])
  })

  it('is deterministic, because these pages are prerendered then hydrated', () => {
    const a = rotatingSiblings(competitors, 4, SIBLING_COUNT).map((c) => c.slug)
    const b = rotatingSiblings(competitors, 4, SIBLING_COUNT).map((c) => c.slug)
    expect(a).toEqual(b)
  })
})

describe('the real page sets', () => {
  it('spreads comparison links evenly across all ten competitors', () => {
    const counts = new Map(competitors.map((c) => [c.slug, 0]))
    competitors.forEach((_, i) => {
      for (const s of rotatingSiblings(competitors, i, SIBLING_COUNT)) {
        counts.set(s.slug, (counts.get(s.slug) ?? 0) + 1)
      }
    })
    expect([...new Set(counts.values())]).toEqual([SIBLING_COUNT])
  })

  it('spreads what-to-do links evenly across all guides', () => {
    const counts = new Map(whatToDoPages.map((p) => [p.slug, 0]))
    whatToDoPages.forEach((_, i) => {
      for (const s of rotatingSiblings(whatToDoPages, i, SIBLING_COUNT)) {
        counts.set(s.slug, (counts.get(s.slug) ?? 0) + 1)
      }
    })
    expect([...new Set(counts.values())]).toEqual([SIBLING_COUNT])
  })
})
