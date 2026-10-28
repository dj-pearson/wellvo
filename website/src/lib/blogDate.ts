/**
 * Format a post date the same way on the build machine and in every browser.
 *
 * toLocaleDateString(undefined, …) used the runtime's locale and time zone, so
 * the prerendered HTML (build machine, UTC, en-US) and the visitor's first
 * render (their locale, their zone) could disagree — a hydration mismatch, and
 * a post published late in the UTC day showed as the previous day in the
 * Americas. Pinning both makes the output a pure function of the timestamp.
 */
export function formatPostDate(iso: string, month: 'short' | 'long' = 'long'): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ''
  return d.toLocaleDateString('en-US', {
    year: 'numeric', month, day: 'numeric', timeZone: 'UTC',
  })
}
