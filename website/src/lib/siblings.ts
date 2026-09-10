/**
 * Even internal-link distribution across a set of sibling pages (US-SEO010).
 *
 * The comparison pages picked their "Related comparisons" block with
 * `competitors.filter(c => c.slug !== slug).slice(0, 3)`. Because the source
 * array order never changes, all ten pages pointed at the same first three
 * entries. Counted over the prerendered output that produced 14 inbound links
 * for Life Alert, 12 for Life360, 11 for Snug Safety — and exactly one, from
 * the hub, for the other six. The pages the pSEO strategy is built on were the
 * ones receiving no internal links at all.
 *
 * Rotating instead of slicing fixes it arithmetically rather than by taste:
 * taking the next `count` entries after the current index, wrapping around,
 * means every item appears in exactly `count` sibling blocks. No item can be
 * starved and none can hog, whatever the array order is.
 *
 * Deterministic on purpose. These pages are prerendered and then hydrated, so
 * a random or date-seeded choice would render one set on the server and a
 * different one on the client — a hydration mismatch, and a link graph that
 * changes on every build for no reason.
 */
export function rotatingSiblings<T>(items: readonly T[], currentIndex: number, count: number): T[] {
  const n = items.length
  if (n <= 1 || count <= 0 || currentIndex < 0 || currentIndex >= n) return []
  const take = Math.min(count, n - 1)
  const out: T[] = []
  for (let step = 1; step <= take; step++) {
    out.push(items[(currentIndex + step) % n])
  }
  return out
}
