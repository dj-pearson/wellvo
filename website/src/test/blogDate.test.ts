import { describe, it, expect } from 'vitest'
import { formatPostDate } from '../lib/blogDate'

describe('formatPostDate', () => {
  it('formats in en-US regardless of runtime locale', () => {
    expect(formatPostDate('2026-03-05T12:00:00Z')).toBe('March 5, 2026')
    expect(formatPostDate('2026-03-05T12:00:00Z', 'short')).toBe('Mar 5, 2026')
  })

  it('uses the UTC calendar day, not the runtime time zone', () => {
    // Late in the UTC day: a browser in the Americas would otherwise render
    // the 4th while the prerender (UTC) rendered the 5th.
    expect(formatPostDate('2026-03-05T23:30:00Z')).toBe('March 5, 2026')
    expect(formatPostDate('2026-03-05T00:15:00+02:00')).toBe('March 4, 2026')
  })

  it('returns an empty string for an unparseable date', () => {
    expect(formatPostDate('not a date')).toBe('')
  })
})
