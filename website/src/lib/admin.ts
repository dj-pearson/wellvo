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
  created_at: string
  updated_at: string
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

export function createPost(post: Partial<BlogPost>) {
  return callEdge<{ post: BlogPost }>('/admin-blog', { action: 'create', post })
}

export function updatePost(id: string, post: Partial<BlogPost>) {
  return callEdge<{ post: BlogPost }>('/admin-blog', { action: 'update', id, post })
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
