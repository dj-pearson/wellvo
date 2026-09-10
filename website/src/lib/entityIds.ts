/**
 * Stable @id values for the three sitewide JSON-LD nodes (US-SEO015).
 *
 * Those nodes — SoftwareApplication, Organization, WebSite — are emitted on
 * every page from STATIC_HEAD in pages/+onRenderHtml.tsx. Without @id they are
 * three anonymous islands, and a per-page Article that wants to name its
 * publisher has to re-declare a second, partial Organization. Two Organization
 * nodes on one page describing the same company is exactly the ambiguity
 * US-WEB012 is fighting, where Search Console shows the brand ranking 2.13 for
 * its own name.
 *
 * With stable @ids, a page-level node points at the sitewide one by reference
 * and the whole page resolves to a single graph.
 *
 * These strings are duplicated in the STATIC_HEAD literal, which is a plain
 * template string and cannot import. src/test/entityGraph.test.ts asserts the
 * two stay identical.
 */
export const SITE_ORIGIN = 'https://dailyok.net'

export const ORGANIZATION_ID = `${SITE_ORIGIN}/#organization`
export const WEBSITE_ID = `${SITE_ORIGIN}/#website`
export const APPLICATION_ID = `${SITE_ORIGIN}/#application`

/**
 * The editorial team is a DISTINCT node with its own @id, not the company
 * under a different label. Reusing ORGANIZATION_ID and relabelling it "Daily
 * OK Editorial Team" would assert that one @id has two names, which is a
 * contradiction in the graph rather than a nuance — and it is the sort of
 * thing that reads fine in a diff and only shows up when the JSON-LD is
 * actually resolved. It hangs off the company via parentOrganization.
 */
export const EDITORIAL_TEAM_ID = `${SITE_ORIGIN}/#editorial-team`
