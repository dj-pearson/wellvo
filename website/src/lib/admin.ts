import { callEdge } from './api'

// =============================================================================
// Types
// =============================================================================

export interface DashboardMetrics {
  total_users: number
  total_families: number
  total_members: number
  checkins_today: number
  checkins_7d: number
  new_users_7d: number
  new_users_30d: number
  active_subscriptions: number
  free_families: number
  paid_families: number
  pending_requests: number
  missed_requests_7d: number
  published_posts: number
  draft_posts: number
  social_posts_scheduled: number
  social_posts_posted_7d: number
  generated_at: string
}

export interface DailyPoint {
  day: string
  new_users: number
  new_families: number
  checkins: number
  missed: number
}

export interface AdminUser {
  id: string
  email: string | null
  phone: string | null
  display_name: string
  role: string
  is_system_admin: boolean
  timezone: string
  created_at: string
  updated_at: string
}

export interface SeoScoreComponent {
  key: string
  label: string
  earned: number
  max: number
  detail: string
}

export interface SeoScoreResult {
  score: number
  breakdown: SeoScoreComponent[]
  hints: string[]
  scored_at: string
  primary_keyword: string | null
}

export interface SeoScoreMeta {
  breakdown: SeoScoreComponent[]
  hints: string[]
  scored_at: string
  primary_keyword: string | null
}

export interface QaCheck {
  id: string
  label: string
  severity: 'error' | 'warning' | 'info'
  passed: boolean
  message: string
  details?: unknown
}

export interface QaResult {
  checks: QaCheck[]
  errorCount: number
  warningCount: number
  infoCount: number
  passedCount: number
  canPublish: boolean
  ranAt: string
}

export interface BlogPost {
  id: string
  slug: string
  title: string
  excerpt: string | null
  content_html: string
  content_json: unknown
  featured_image_url: string | null
  status: 'draft' | 'published' | 'archived'
  published_at: string | null
  author_id: string | null
  seo_title: string | null
  seo_description: string | null
  canonical_url: string | null
  og_image_url: string | null
  tags: string[]
  category: string | null
  ai_generated: boolean
  ai_meta: unknown
  view_count: number
  seo_score: number | null
  seo_score_meta: SeoScoreMeta | null
  created_at: string
  updated_at: string
}

export interface BlogPostListItem {
  id: string
  slug: string
  title: string
  excerpt: string | null
  status: BlogPost['status']
  published_at: string | null
  featured_image_url: string | null
  tags: string[]
  category: string | null
  ai_generated: boolean
  view_count: number
  seo_score: number | null
  author_id: string | null
  created_at: string
  updated_at: string
}

export interface BlogTemplate {
  id: string
  name: string
  description: string | null
  system_prompt: string
  user_prompt_template: string
  slug_template: string | null
  title_template: string | null
  default_tags: string[]
  default_category: string | null
  created_by: string | null
  created_at: string
  updated_at: string
}

export interface BlogPostRevisionSummary {
  id: string
  post_id: string
  editor_id: string | null
  title: string
  slug: string
  status: BlogPost['status']
  reason: string
  parent_revision_id: string | null
  created_at: string
  editor: { display_name: string | null; email: string | null } | null
}

export interface BlogPostRevision extends BlogPost {
  // blog_post_revisions adds these on top of the post snapshot
  post_id: string
  editor_id: string | null
  reason: string
  parent_revision_id: string | null
}

export interface SocialPost {
  id: string
  content: string
  platforms: string[]
  status: 'draft' | 'scheduled' | 'publishing' | 'posted' | 'failed'
  scheduled_at: string | null
  posted_at: string | null
  media_urls: string[]
  link_url: string | null
  webhook_url: string | null
  webhook_response: unknown
  webhook_error: string | null
  post_urls: Record<string, string> | null
  author_id: string | null
  source_post_id: string | null
  variant_meta: Record<string, unknown> | null
  created_at: string
  updated_at: string
}

export type SyndicationPlatform = 'x' | 'linkedin' | 'facebook' | 'pinterest'

export interface SyndicationResult {
  drafts: SocialPost[]
  variant_count: number
  ai_meta: Record<string, unknown>
}

export interface AiArticle {
  title: string
  slug: string
  excerpt: string
  seo_title: string
  seo_description: string
  tags: string[]
  category: string
  content_html: string
}

export interface BlogBankInProgress {
  id: string
  title: string
  claimed_at: string | null
}

export interface BlogBankStatus {
  pending: number
  generating: number
  published: number
  failed: number
  skipped: number
  total: number
  in_progress: BlogBankInProgress[]
}

export interface BlogGenerationStarted {
  started: true
  source: 'blog_title_bank' | 'fallback'
  title_bank_id: string | null
  title: string | null
  message: string
}

export interface BlogGenerationResult {
  source: 'blog_title_bank' | 'fallback'
  post_id: string
  slug: string
  title: string
  excerpt: string | null
  url: string
  content_html: string
  topic_rationale: string | null
  remaining_pending: number
  ai_meta: Record<string, unknown>
}

// =============================================================================
// Metrics
// =============================================================================

export function loadMetrics(days = 30) {
  const url = `/admin-metrics?days=${days}`
  return callEdge<{ metrics: DashboardMetrics; timeseries: DailyPoint[] }>(url)
}

// =============================================================================
// Users
// =============================================================================

export function listUsers(opts: { search?: string; limit?: number; offset?: number } = {}) {
  return callEdge<{ users: AdminUser[]; total: number; limit: number; offset: number }>(
    '/admin-users',
    { action: 'list', ...opts },
  )
}

export interface FamilyTreeMember {
  member_id: string
  role: string
  status: string
  joined_at: string | null
  user: AdminUser
}

export interface FamilyTreeNode {
  id: string
  name: string
  subscription_tier: string
  subscription_status: string
  max_receivers: number
  created_at: string
  owner: AdminUser | null
  members: FamilyTreeMember[]
}

export function listFamilyTree(opts: { search?: string } = {}) {
  return callEdge<{
    families: FamilyTreeNode[]
    orphans: AdminUser[]
    total_families: number
    total_orphans: number
  }>('/admin-users', { action: 'list_family_tree', ...opts })
}

export function getUser(user_id: string) {
  return callEdge<{
    user: AdminUser & { is_system_admin: boolean }
    families_owned: Array<Record<string, unknown>>
    memberships: Array<Record<string, unknown>>
    recent_checkins: Array<Record<string, unknown>>
    recent_requests: Array<Record<string, unknown>>
  }>('/admin-users', { action: 'get', user_id })
}

export function setUserAdmin(user_id: string, is_system_admin: boolean) {
  return callEdge<{ success: true }>('/admin-users', {
    action: 'set_admin',
    user_id,
    is_system_admin,
  })
}

// =============================================================================
// Blog posts
// =============================================================================

export function listPosts(opts: {
  status?: 'draft' | 'published' | 'archived' | 'all'
  limit?: number
  offset?: number
} = {}) {
  return callEdge<{ posts: BlogPostListItem[]; total: number; limit: number; offset: number }>(
    '/admin-blog',
    { action: 'list', ...opts },
  )
}

export function getPost(id: string) {
  return callEdge<{ post: BlogPost }>('/admin-blog', { action: 'get', id })
}

export function createPost(post: Partial<BlogPost>, opts: { force?: boolean } = {}) {
  return callEdge<{ post: BlogPost; qa: QaResult | null }>('/admin-blog', {
    action: 'create', post,
    ...(opts.force ? { force: true } : {}),
  })
}

export function updatePost(id: string, post: Partial<BlogPost>, opts: { force?: boolean } = {}) {
  return callEdge<{ post: BlogPost; qa: QaResult | null }>('/admin-blog', {
    action: 'update', id, post,
    ...(opts.force ? { force: true } : {}),
  })
}

export function deletePost(id: string) {
  return callEdge<{ success: true }>('/admin-blog', { action: 'delete', id })
}

// Templates
export function listTemplates() {
  return callEdge<{ templates: BlogTemplate[] }>('/admin-blog', { action: 'list_templates' })
}

export function saveTemplate(template: Partial<BlogTemplate> & { name: string; system_prompt: string; user_prompt_template: string }) {
  return callEdge<{ template: BlogTemplate }>('/admin-blog', { action: 'save_template', template })
}

export function deleteTemplate(template_id: string) {
  return callEdge<{ success: true }>('/admin-blog', { action: 'delete_template', template_id })
}

// =============================================================================
// Blog post revisions (US-BLOG-009)
// =============================================================================

export function listRevisions(post_id: string, opts: { limit?: number; offset?: number } = {}) {
  return callEdge<{
    revisions: BlogPostRevisionSummary[]
    total: number
    limit: number
    offset: number
  }>('/admin-blog', { action: 'list_revisions', post_id, ...opts })
}

export function getRevision(revision_id: string) {
  return callEdge<{ revision: BlogPostRevision }>('/admin-blog', {
    action: 'get_revision',
    revision_id,
  })
}

export function restoreRevision(revision_id: string) {
  return callEdge<{ post: BlogPost; restored_from: string }>('/admin-blog', {
    action: 'restore_revision',
    revision_id,
  })
}

// =============================================================================
// SEO score (US-BLOG-033)
// =============================================================================

/** Preview a score without persisting — pass either an id or a draft post body. */
export function scorePost(args: { id?: string; post?: Partial<BlogPost> }) {
  return callEdge<{ result: SeoScoreResult }>('/admin-blog', {
    action: 'score_post',
    ...args,
  })
}

/** Re-score every post and persist results. Returns counts. */
export function rescoreAll() {
  return callEdge<{ updated: number; failed: number; total: number }>('/admin-blog', {
    action: 'rescore_all',
  })
}

// =============================================================================
// Pre-publish QA (US-BLOG-040)
// =============================================================================

/** Run the pre-publish checklist without saving. */
export function qaPost(args: { id?: string; post?: Partial<BlogPost> }) {
  return callEdge<{ result: QaResult }>('/admin-blog', { action: 'qa_post', ...args })
}

/** Pull the QaResult out of a 422 ApiError raised by createPost/updatePost. */
export function qaFromError(err: unknown): QaResult | null {
  if (
    err && typeof err === 'object' && 'details' in err &&
    err.details && typeof err.details === 'object' && 'qa' in err.details &&
    err.details.qa && typeof err.details.qa === 'object'
  ) {
    return (err.details as { qa: QaResult }).qa
  }
  return null
}

// =============================================================================
// Syndication (US-BLOG-044/045/046/048)
// =============================================================================

export function syndicatePost(post_id: string, platforms: SyndicationPlatform[]) {
  return callEdge<SyndicationResult>('/admin-blog', {
    action: 'syndicate_post',
    id: post_id,
    platforms,
  })
}

// =============================================================================
// Refresh queue (US-BLOG-063 / US-BLOG-066)
// =============================================================================

export type RefreshReason = 'decay' | 'serp_change' | 'stale_facts' | 'manual' | 'periodic'
export type RefreshStatus = 'queued' | 'in_progress' | 'proposed' | 'done' | 'dismissed'

export interface RefreshQueueItem {
  id: string
  post_id: string
  reason: RefreshReason
  status: RefreshStatus
  detection_meta: Record<string, unknown> | null
  proposal_revision_id: string | null
  proposal_summary: string | null
  actioned_by: string | null
  actioned_at: string | null
  notes: string | null
  created_at: string
  updated_at: string
  post: { slug: string; title: string; seo_score: number | null } | null
}

export function listRefreshQueue(opts: { filter?: 'open' | RefreshStatus | 'all'; limit?: number; offset?: number } = {}) {
  return callEdge<{ items: RefreshQueueItem[]; total: number; limit: number; offset: number; filter: string }>(
    '/admin-blog',
    { action: 'list_refresh_queue', refresh_status_filter: opts.filter ?? 'open', limit: opts.limit, offset: opts.offset },
  )
}

export function actionRefreshQueue(refresh_queue_id: string, refresh_action: 'in_progress' | 'dismissed' | 'done' | 'queued', reason?: string) {
  return callEdge<{ item: RefreshQueueItem }>('/admin-blog', {
    action: 'action_refresh_queue', refresh_queue_id, refresh_action, reason,
  })
}

export function triggerRefreshProposal(refresh_queue_id: string) {
  return callEdge<{
    revision_id: string
    change_summary: string
    queue_id: string
    history_url: string
    ai_meta: Record<string, unknown>
  }>('/admin-blog', { action: 'trigger_refresh_proposal', refresh_queue_id })
}

// =============================================================================
// Per-post metrics (US-BLOG-061)
// =============================================================================

export interface PostMetricRow {
  metric_date: string
  source: 'search_console' | 'ga4' | 'internal'
  impressions: number
  clicks: number
  avg_position: number | null
  ctr: number | null
  sessions: number
  engaged_sessions: number
  conversions: number
  avg_time_on_page_seconds: number | null
}

export interface PostMetricsSummary {
  clicks_28d: number
  impressions_28d: number
  sessions_28d: number
  conversions_28d: number
  days: number
}

export function listPostMetrics(post_id: string, days = 90) {
  return callEdge<{ rows: PostMetricRow[]; summary: PostMetricsSummary }>('/admin-blog', {
    action: 'list_post_metrics', id: post_id, metric_days: days,
  })
}

// =============================================================================
// AI generation
// =============================================================================

export function generateArticle(params: { prompt?: string; keyword?: string }) {
  return callEdge<{ article: AiArticle; ai_meta: Record<string, unknown> }>(
    '/admin-blog-ai',
    { action: 'generate_article', ...params },
  )
}

export function generateFromTemplate(params: {
  template_id: string
  variables: Record<string, string>
  save_as_draft?: boolean
}) {
  return callEdge<{
    article: AiArticle
    ai_meta: Record<string, unknown>
    post?: { id: string; slug: string }
  }>('/admin-blog-ai', { action: 'generate_from_template', ...params })
}

export function batchGenerate(params: { template_id: string; batch: Array<Record<string, string>> }) {
  return callEdge<{
    results: Array<{ variables: Record<string, string>; post_id?: string; slug?: string; error?: string }>
  }>('/admin-blog-ai', { action: 'batch_generate', ...params })
}

export function improveText(text: string, instruction?: string) {
  return callEdge<{ text: string; provider: string; model: string }>(
    '/admin-blog-ai',
    { action: 'improve_text', text, instruction },
  )
}

export function generateSeoMeta(params: { title?: string; text?: string }) {
  return callEdge<{ seo_title: string; seo_description: string }>(
    '/admin-blog-ai',
    { action: 'generate_seo_meta', ...params },
  )
}

export function getBlogBankStatus() {
  return callEdge<BlogBankStatus>('/admin-blog-ai', { action: 'bank_status' })
}

export function generateNextFromBank(params: { topic?: string; skip_bank?: boolean } = {}) {
  return callEdge<BlogGenerationStarted>('/admin-blog-ai', {
    action: 'generate_next_from_bank',
    ...params,
  })
}

// =============================================================================
// Social posts
// =============================================================================

export function listSocial(opts: {
  status?: 'draft' | 'scheduled' | 'posted' | 'failed' | 'all'
  limit?: number
  offset?: number
} = {}) {
  return callEdge<{ posts: SocialPost[]; total: number; limit: number; offset: number }>(
    '/admin-social',
    { action: 'list', ...opts },
  )
}

export function createSocial(post: Partial<SocialPost>) {
  return callEdge<{ post: SocialPost }>('/admin-social', { action: 'create', post })
}

export function updateSocial(id: string, post: Partial<SocialPost>) {
  return callEdge<{ post: SocialPost }>('/admin-social', { action: 'update', id, post })
}

export function deleteSocial(id: string) {
  return callEdge<{ success: true }>('/admin-social', { action: 'delete', id })
}

export function publishSocial(id: string) {
  return callEdge<{ post: SocialPost }>('/admin-social', { action: 'publish', id })
}
