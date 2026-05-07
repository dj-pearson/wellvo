import { useEffect, useState, type FormEvent, type CSSProperties } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useEditor, EditorContent } from '@tiptap/react'
import StarterKit from '@tiptap/starter-kit'
import Link from '@tiptap/extension-link'
import Image from '@tiptap/extension-image'
import Placeholder from '@tiptap/extension-placeholder'
import Typography from '@tiptap/extension-typography'
import {
  Bold, Italic, Strikethrough, List, ListOrdered, Quote,
  Heading2, Heading3, Undo, Redo, Link as LinkIcon, Image as ImageIcon,
  Sparkles, Save, History, Gauge, AlertCircle, CheckCircle2, ShieldCheck, Info, MessageSquare, Share2,
} from 'lucide-react'
import {
  createPost, updatePost, getPost, generateArticle, generateSeoMeta, improveText, scorePost, qaPost, qaFromError, syndicatePost,
  type BlogPost, type SeoScoreResult, type QaResult, type SyndicationPlatform,
} from '../lib/admin'
import { TagInput } from './TagInput'
import './admin.css'

type Mode = 'new' | 'edit'

interface Draft {
  title: string
  slug: string
  excerpt: string
  content_html: string
  featured_image_url: string
  seo_title: string
  seo_description: string
  tags: string[]
  category: string
  status: BlogPost['status']
  ai_generated: boolean
  ai_meta: unknown
}

const emptyDraft: Draft = {
  title: '',
  slug: '',
  excerpt: '',
  content_html: '',
  featured_image_url: '',
  seo_title: '',
  seo_description: '',
  tags: [],
  category: '',
  status: 'draft',
  ai_generated: false,
  ai_meta: null,
}

export default function AdminBlogEditor() {
  const { id } = useParams<{ id: string }>()
  const mode: Mode = id && id !== 'new' ? 'edit' : 'new'
  const navigate = useNavigate()
  const [draft, setDraft] = useState<Draft>(emptyDraft)
  const [postId, setPostId] = useState<string | null>(null)
  const [loading, setLoading] = useState(mode === 'edit')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [qa, setQa] = useState<QaResult | null>(null)
  const [qaRunning, setQaRunning] = useState(false)
  const [showQa, setShowQa] = useState(false)
  const [qaBlocked, setQaBlocked] = useState(false)
  const [syndicateOpen, setSyndicateOpen] = useState(false)
  const [syndicating, setSyndicating] = useState(false)
  const [syndicateMsg, setSyndicateMsg] = useState<string | null>(null)
  const [syndicatePlatforms, setSyndicatePlatforms] = useState<SyndicationPlatform[]>(['x', 'linkedin'])

  const editor = useEditor({
    extensions: [
      StarterKit.configure({ heading: { levels: [2, 3] } }),
      Link.configure({ openOnClick: false, autolink: true, HTMLAttributes: { rel: 'noopener noreferrer' } }),
      Image,
      Placeholder.configure({ placeholder: 'Start writing, or use the AI panel →' }),
      Typography,
    ],
    content: '',
    onUpdate: ({ editor: e }) => {
      setDraft((d) => ({ ...d, content_html: e.getHTML() }))
    },
  })

  useEffect(() => {
    if (mode === 'edit' && id) {
      let cancelled = false
      getPost(id)
        .then((res) => {
          if (cancelled) return
          const p = res.post
          setPostId(p.id)
          setDraft({
            title: p.title,
            slug: p.slug,
            excerpt: p.excerpt ?? '',
            content_html: p.content_html,
            featured_image_url: p.featured_image_url ?? '',
            seo_title: p.seo_title ?? '',
            seo_description: p.seo_description ?? '',
            tags: p.tags ?? [],
            category: p.category ?? '',
            status: p.status,
            ai_generated: p.ai_generated,
            ai_meta: p.ai_meta,
          })
          editor?.commands.setContent(p.content_html || '', false)
        })
        .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load post'))
        .finally(() => setLoading(false))
      return () => { cancelled = true }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, mode, editor])

  const save = async (e: FormEvent | null, overrides: Partial<Draft> = {}, opts: { force?: boolean } = {}) => {
    e?.preventDefault()
    setSaving(true)
    setError(null)
    setSuccess(null)
    setQaBlocked(false)
    try {
      const payload = { ...draft, ...overrides }
      const postBody = {
        title: payload.title,
        slug: payload.slug || undefined,
        excerpt: payload.excerpt || null,
        content_html: payload.content_html,
        featured_image_url: payload.featured_image_url || null,
        seo_title: payload.seo_title || null,
        seo_description: payload.seo_description || null,
        tags: payload.tags,
        category: payload.category || null,
        status: payload.status,
        ai_generated: payload.ai_generated,
        ai_meta: payload.ai_meta as BlogPost['ai_meta'],
      }
      if (mode === 'new' || !postId) {
        const res = await createPost(postBody, opts)
        setPostId(res.post.id)
        setDraft((d) => ({ ...d, slug: res.post.slug, status: res.post.status, ...overrides }))
        if (res.qa) setQa(res.qa)
        setSuccess(opts.force ? 'Created (QA overridden)' : 'Created')
        navigate(`/admin/blog/${res.post.id}`, { replace: true })
      } else {
        const res = await updatePost(postId, postBody, opts)
        setDraft((d) => ({ ...d, slug: res.post.slug, status: res.post.status, ...overrides }))
        if (res.qa) setQa(res.qa)
        setSuccess(opts.force ? 'Saved (QA overridden)' : 'Saved')
      }
    } catch (err) {
      // Pre-publish QA returned 422 — pull the QaResult, surface in the QA
      // panel, and let the user fix or force-override. Server is the source
      // of truth; the panel reflects what the server saw.
      const qaPayload = qaFromError(err)
      if (qaPayload) {
        setQa(qaPayload)
        setShowQa(true)
        setQaBlocked(true)
        setError(`Pre-publish QA blocked the publish — ${qaPayload.errorCount} error(s) to fix.`)
      } else {
        setError(err instanceof Error ? err.message : 'Failed to save')
      }
    } finally {
      setSaving(false)
    }
  }

  const runSyndication = async () => {
    if (!postId) {
      setSyndicateMsg('Save the post first.')
      return
    }
    if (syndicatePlatforms.length === 0) {
      setSyndicateMsg('Pick at least one platform.')
      return
    }
    setSyndicating(true)
    setSyndicateMsg(null)
    try {
      const res = await syndicatePost(postId, syndicatePlatforms)
      setSyndicateMsg(`Generated ${res.variant_count} draft${res.variant_count === 1 ? '' : 's'}. View on the Social page.`)
      setSyndicateOpen(false)
    } catch (err) {
      setSyndicateMsg(err instanceof Error ? err.message : 'Syndication failed')
    } finally {
      setSyndicating(false)
    }
  }

  const runQaNow = async () => {
    setQaRunning(true)
    try {
      const args = postId
        ? { id: postId }
        : {
            post: {
              title: draft.title,
              slug: draft.slug || undefined,
              excerpt: draft.excerpt || null,
              content_html: draft.content_html,
              featured_image_url: draft.featured_image_url || null,
              seo_title: draft.seo_title || null,
              seo_description: draft.seo_description || null,
              tags: draft.tags,
              category: draft.category || null,
              status: draft.status,
              ai_meta: draft.ai_meta as BlogPost['ai_meta'],
            },
          }
      const res = await qaPost(args)
      setQa(res.result)
      setShowQa(true)
      setQaBlocked(false)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'QA check failed')
    } finally {
      setQaRunning(false)
    }
  }

  if (loading) return <div className="admin-empty">Loading post…</div>

  return (
    <>
      <div className="admin-page-header">
        <div>
          <div className="admin-page-title">{mode === 'new' ? 'New post' : 'Edit post'}</div>
          {draft.status && (
            <div className="admin-page-subtitle">
              Status: <strong>{draft.status}</strong>
              {draft.ai_generated && <span className="admin-ai-chip" style={{ marginLeft: 10 }}>AI-generated</span>}
            </div>
          )}
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <button
            className="admin-btn admin-btn-secondary"
            onClick={() => navigate('/admin/blog')}
            type="button"
          >
            Back
          </button>
          {mode === 'edit' && postId && (
            <button
              className="admin-btn admin-btn-secondary"
              onClick={() => navigate(`/admin/blog/${postId}/history`)}
              type="button"
              title="View revision history"
            >
              <History size={14} /> History
            </button>
          )}
          {mode === 'edit' && postId && (
            <button
              className="admin-btn admin-btn-secondary"
              onClick={() => setSyndicateOpen(true)}
              type="button"
              title="Generate per-platform syndication drafts"
            >
              <Share2 size={14} /> Syndicate
            </button>
          )}
          <button
            className="admin-btn admin-btn-secondary"
            onClick={() => void runQaNow()}
            disabled={qaRunning || (!draft.title && !draft.content_html)}
            type="button"
            title="Run pre-publish QA"
          >
            <ShieldCheck size={14} /> {qaRunning ? 'Checking…' : 'Run QA'}
          </button>
          <button
            className="admin-btn admin-btn-secondary"
            onClick={(e) => save(e, { status: 'draft' })}
            disabled={saving}
            type="button"
          >
            <Save size={14} /> Save draft
          </button>
          <button
            className="admin-btn admin-btn-primary"
            onClick={(e) => save(e, { status: 'published' })}
            disabled={saving || !draft.title}
            type="button"
          >
            {draft.status === 'published' ? 'Update' : 'Publish'}
          </button>
        </div>
      </div>

      {error && <div className="admin-error">{error}</div>}
      {success && <div className="admin-success">{success}</div>}

      <div className="admin-editor-grid">
        <form className="admin-form" onSubmit={(e) => save(e)}>
          <div>
            <label className="admin-label" htmlFor="post-title">Title</label>
            <input
              id="post-title"
              type="text"
              className="admin-input"
              value={draft.title}
              onChange={(e) => setDraft({ ...draft, title: e.target.value })}
              placeholder="Give the post a clear, compelling title"
              required
            />
          </div>

          <div>
            <label className="admin-label" htmlFor="post-excerpt">Excerpt</label>
            <textarea
              id="post-excerpt"
              className="admin-textarea"
              value={draft.excerpt}
              onChange={(e) => setDraft({ ...draft, excerpt: e.target.value })}
              placeholder="140–180 chars — shown on the blog index and in shares"
            />
          </div>

          <div>
            <label className="admin-label">Body</label>
            <EditorToolbar editor={editor} />
            <div className="admin-editor-surface">
              <EditorContent editor={editor} />
            </div>
          </div>

          <div className="admin-form-row">
            <div>
              <label className="admin-label" htmlFor="post-slug">Slug</label>
              <input
                id="post-slug"
                type="text"
                className="admin-input"
                value={draft.slug}
                onChange={(e) => setDraft({ ...draft, slug: e.target.value })}
                placeholder="auto-generated from title if blank"
              />
            </div>
            <div>
              <label className="admin-label" htmlFor="post-category">Category</label>
              <input
                id="post-category"
                type="text"
                className="admin-input"
                value={draft.category}
                onChange={(e) => setDraft({ ...draft, category: e.target.value })}
              />
            </div>
          </div>

          <div>
            <label className="admin-label">Tags</label>
            <TagInput tags={draft.tags} onChange={(tags) => setDraft({ ...draft, tags })} />
          </div>

          <div>
            <label className="admin-label" htmlFor="post-featured">Featured image URL</label>
            <input
              id="post-featured"
              type="url"
              className="admin-input"
              value={draft.featured_image_url}
              onChange={(e) => setDraft({ ...draft, featured_image_url: e.target.value })}
              placeholder="https://…"
            />
          </div>

          <details style={{ borderTop: '1px solid var(--gray-200)', paddingTop: 16 }}>
            <summary style={{ cursor: 'pointer', fontWeight: 600, color: 'var(--gray-700)' }}>SEO</summary>
            <div className="admin-form" style={{ marginTop: 12 }}>
              <div>
                <label className="admin-label" htmlFor="seo-title">SEO title</label>
                <input
                  id="seo-title"
                  type="text"
                  className="admin-input"
                  value={draft.seo_title}
                  onChange={(e) => setDraft({ ...draft, seo_title: e.target.value })}
                />
              </div>
              <div>
                <label className="admin-label" htmlFor="seo-desc">SEO description</label>
                <textarea
                  id="seo-desc"
                  className="admin-textarea"
                  value={draft.seo_description}
                  onChange={(e) => setDraft({ ...draft, seo_description: e.target.value })}
                />
              </div>
              <GenerateSeoButton draft={draft} onResult={(meta) => setDraft({ ...draft, ...meta })} />
            </div>
          </details>
        </form>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <AiPanel
            onArticle={(article, ai_meta) => {
              setDraft((d) => ({
                ...d,
                title: article.title || d.title,
                slug: article.slug || d.slug,
                excerpt: article.excerpt || d.excerpt,
                seo_title: article.seo_title || d.seo_title,
                seo_description: article.seo_description || d.seo_description,
                tags: Array.isArray(article.tags) && article.tags.length > 0 ? article.tags : d.tags,
                category: article.category || d.category,
                content_html: article.content_html || d.content_html,
                ai_generated: true,
                ai_meta,
              }))
              editor?.commands.setContent(article.content_html || '', true)
            }}
            onImprove={(newText) => {
              const sel = editor?.state.selection
              if (sel && !sel.empty && editor) {
                editor.chain().focus().deleteSelection().insertContent(newText).run()
              } else {
                editor?.chain().focus().insertContent(newText).run()
              }
            }}
            editor={editor}
          />
          <SeoScorePanel draft={draft} />
          <CritiqueLogPanel aiMeta={draft.ai_meta} />
          {(showQa || qa) && (
            <QaPanel
              qa={qa}
              running={qaRunning}
              blocked={qaBlocked}
              saving={saving}
              onRerun={() => void runQaNow()}
              onForcePublish={() => {
                if (!confirm('Publish despite QA errors? The override will be recorded in the audit log.')) return
                void save(null, { status: 'published' }, { force: true })
              }}
              onClose={() => { setShowQa(false); setQaBlocked(false) }}
            />
          )}
        </div>
      </div>

      {syndicateOpen && (
        <SyndicateDialog
          platforms={syndicatePlatforms}
          onChangePlatforms={setSyndicatePlatforms}
          syndicating={syndicating}
          message={syndicateMsg}
          onClose={() => setSyndicateOpen(false)}
          onConfirm={() => void runSyndication()}
        />
      )}
      {!syndicateOpen && syndicateMsg && (
        <div className="admin-success" style={{ marginTop: 12 }}>{syndicateMsg}</div>
      )}
    </>
  )
}

// =============================================================================
// Toolbar
// =============================================================================

function EditorToolbar({ editor }: { editor: ReturnType<typeof useEditor> }) {
  if (!editor) return null

  const btn = (active: boolean, onClick: () => void, Icon: typeof Bold, label: string) => (
    <button type="button" className={active ? 'is-active' : ''} onClick={onClick} aria-label={label} title={label}>
      <Icon size={14} />
    </button>
  )

  return (
    <div className="admin-editor-toolbar">
      {btn(editor.isActive('heading', { level: 2 }), () => editor.chain().focus().toggleHeading({ level: 2 }).run(), Heading2, 'Heading 2')}
      {btn(editor.isActive('heading', { level: 3 }), () => editor.chain().focus().toggleHeading({ level: 3 }).run(), Heading3, 'Heading 3')}
      <span className="sep" />
      {btn(editor.isActive('bold'), () => editor.chain().focus().toggleBold().run(), Bold, 'Bold')}
      {btn(editor.isActive('italic'), () => editor.chain().focus().toggleItalic().run(), Italic, 'Italic')}
      {btn(editor.isActive('strike'), () => editor.chain().focus().toggleStrike().run(), Strikethrough, 'Strikethrough')}
      <span className="sep" />
      {btn(editor.isActive('bulletList'), () => editor.chain().focus().toggleBulletList().run(), List, 'Bullet list')}
      {btn(editor.isActive('orderedList'), () => editor.chain().focus().toggleOrderedList().run(), ListOrdered, 'Numbered list')}
      {btn(editor.isActive('blockquote'), () => editor.chain().focus().toggleBlockquote().run(), Quote, 'Quote')}
      <span className="sep" />
      <button
        type="button"
        onClick={() => {
          const url = prompt('Link URL')
          if (url === null) return
          if (url === '') editor.chain().focus().unsetLink().run()
          else editor.chain().focus().extendMarkRange('link').setLink({ href: url }).run()
        }}
        title="Link"
        aria-label="Link"
      >
        <LinkIcon size={14} />
      </button>
      <button
        type="button"
        onClick={() => {
          const url = prompt('Image URL')
          if (url) editor.chain().focus().setImage({ src: url }).run()
        }}
        title="Image"
        aria-label="Image"
      >
        <ImageIcon size={14} />
      </button>
      <span className="sep" />
      <button type="button" onClick={() => editor.chain().focus().undo().run()} title="Undo" aria-label="Undo">
        <Undo size={14} />
      </button>
      <button type="button" onClick={() => editor.chain().focus().redo().run()} title="Redo" aria-label="Redo">
        <Redo size={14} />
      </button>
    </div>
  )
}

// =============================================================================
// AI panel
// =============================================================================

function AiPanel({
  onArticle,
  onImprove,
  editor,
}: {
  onArticle: (article: NonNullable<Awaited<ReturnType<typeof generateArticle>>['article']>, ai_meta: Record<string, unknown>) => void
  onImprove: (text: string) => void
  editor: ReturnType<typeof useEditor>
}) {
  const [prompt, setPrompt] = useState('')
  const [keyword, setKeyword] = useState('')
  const [working, setWorking] = useState(false)
  const [err, setErr] = useState<string | null>(null)

  const generate = async () => {
    setWorking(true)
    setErr(null)
    try {
      const res = await generateArticle({ prompt: prompt || undefined, keyword: keyword || undefined })
      onArticle(res.article, res.ai_meta)
      setPrompt('')
      setKeyword('')
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'AI generation failed')
    } finally {
      setWorking(false)
    }
  }

  const improveSelected = async () => {
    if (!editor) return
    const { from, to } = editor.state.selection
    if (from === to) {
      setErr('Select a passage first')
      return
    }
    const text = editor.state.doc.textBetween(from, to, ' ')
    setWorking(true)
    setErr(null)
    try {
      const res = await improveText(text)
      onImprove(res.text)
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'AI improvement failed')
    } finally {
      setWorking(false)
    }
  }

  return (
    <div className="admin-ai-panel">
      <h3><Sparkles size={14} style={{ marginRight: 4, verticalAlign: 'middle' }} /> AI assistant</h3>
      {err && <div className="admin-error" style={{ marginBottom: 8 }}>{err}</div>}

      <label className="admin-label" htmlFor="ai-keyword">Target keyword / topic</label>
      <input
        id="ai-keyword"
        type="text"
        className="admin-input"
        value={keyword}
        onChange={(e) => setKeyword(e.target.value)}
        placeholder='e.g. "check-in app for elderly parents"'
      />

      <label className="admin-label" style={{ marginTop: 10 }} htmlFor="ai-prompt">Or custom instructions</label>
      <textarea
        id="ai-prompt"
        className="admin-textarea"
        value={prompt}
        onChange={(e) => setPrompt(e.target.value)}
        placeholder="Optional — give specific angle, audience, or points to cover"
      />

      <button
        type="button"
        className="admin-btn admin-btn-primary"
        onClick={generate}
        disabled={working || (!prompt && !keyword)}
        style={{ marginTop: 10, width: '100%' }}
      >
        {working ? 'Generating…' : 'Generate article'}
      </button>

      <div className="admin-help" style={{ marginTop: 10, paddingTop: 10, borderTop: '1px solid var(--gray-100)' }}>
        <strong>Tip:</strong> select text in the body and click <em>Improve selection</em> to rewrite just that passage.
      </div>

      <button
        type="button"
        className="admin-btn admin-btn-secondary"
        onClick={improveSelected}
        disabled={working}
        style={{ marginTop: 8, width: '100%' }}
      >
        Improve selection
      </button>
    </div>
  )
}

function GenerateSeoButton({
  draft,
  onResult,
}: {
  draft: Draft
  onResult: (meta: { seo_title: string; seo_description: string }) => void
}) {
  const [working, setWorking] = useState(false)
  const [err, setErr] = useState<string | null>(null)

  const run = async () => {
    if (!draft.title && !draft.content_html) return
    setWorking(true)
    setErr(null)
    try {
      const res = await generateSeoMeta({
        title: draft.title,
        text: stripTags(draft.content_html).slice(0, 3000),
      })
      onResult({ seo_title: res.seo_title, seo_description: res.seo_description })
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Failed')
    } finally {
      setWorking(false)
    }
  }

  return (
    <>
      {err && <div className="admin-error">{err}</div>}
      <button
        type="button"
        className="admin-btn admin-btn-secondary"
        onClick={run}
        disabled={working || (!draft.title && !draft.content_html)}
      >
        <Sparkles size={14} /> {working ? 'Generating…' : 'Generate SEO meta from content'}
      </button>
    </>
  )
}

function stripTags(html: string): string {
  return html.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim()
}

// =============================================================================
// SEO score panel (US-BLOG-033)
// =============================================================================

function SeoScorePanel({ draft }: { draft: Draft }) {
  const [result, setResult] = useState<SeoScoreResult | null>(null)
  const [scoring, setScoring] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [expanded, setExpanded] = useState(false)

  // Debounce-rescore as the draft changes. 600ms idle is enough to avoid
  // hammering the function while still feeling live.
  useEffect(() => {
    const handle = setTimeout(async () => {
      if (!draft.title && !draft.content_html) { setResult(null); return }
      setScoring(true)
      setErr(null)
      try {
        const res = await scorePost({
          post: {
            title: draft.title,
            slug: draft.slug || undefined,
            excerpt: draft.excerpt || null,
            content_html: draft.content_html,
            seo_title: draft.seo_title || null,
            seo_description: draft.seo_description || null,
            tags: draft.tags,
            ai_meta: draft.ai_meta as BlogPost['ai_meta'],
          },
        })
        setResult(res.result)
      } catch (e) {
        setErr(e instanceof Error ? e.message : 'Failed to score')
      } finally {
        setScoring(false)
      }
    }, 600)
    return () => clearTimeout(handle)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    draft.title, draft.slug, draft.excerpt, draft.content_html,
    draft.seo_title, draft.seo_description, draft.tags.join('|'),
  ])

  const score = result?.score ?? null
  const band = scoreBand(score)

  return (
    <div className="admin-ai-panel">
      <h3>
        <Gauge size={14} style={{ marginRight: 4, verticalAlign: 'middle' }} />
        SEO score
        {scoring && <span style={{ marginLeft: 8, fontSize: 11, color: 'var(--gray-500)' }}>scoring…</span>}
      </h3>

      {err && <div className="admin-error" style={{ marginBottom: 8 }}>{err}</div>}

      {score === null ? (
        <div className="admin-help">Add a title and body to score this post.</div>
      ) : (
        <>
          <div style={{
            display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 8,
          }}>
            <div style={{ fontSize: 36, fontWeight: 700, color: band.color, lineHeight: 1 }}>{score}</div>
            <div style={{ fontSize: 14, color: 'var(--gray-600)' }}>/ 100 — {band.label}</div>
          </div>

          <div style={{
            height: 6, background: 'var(--gray-100)', borderRadius: 3, overflow: 'hidden', marginBottom: 12,
          }}>
            <div style={{ width: `${score}%`, height: '100%', background: band.color }} />
          </div>

          {result && result.hints.length > 0 && (
            <div style={{ marginBottom: 8 }}>
              <div style={{ fontSize: 12, fontWeight: 600, color: 'var(--gray-700)', marginBottom: 4 }}>
                Top fixes
              </div>
              <ul style={{ paddingLeft: 18, margin: 0, fontSize: 12, color: 'var(--gray-700)', lineHeight: 1.5 }}>
                {result.hints.slice(0, 3).map((h, i) => (
                  <li key={i}>{h}</li>
                ))}
              </ul>
            </div>
          )}

          <button
            type="button"
            onClick={() => setExpanded((v) => !v)}
            style={{
              width: '100%', marginTop: 6, padding: '6px 10px', fontSize: 12,
              background: 'transparent', border: '1px solid var(--gray-200)',
              borderRadius: 4, cursor: 'pointer', color: 'var(--gray-700)',
            }}
          >
            {expanded ? 'Hide breakdown' : 'Show breakdown'}
          </button>

          {expanded && result && (
            <div style={{ marginTop: 10, fontSize: 12 }}>
              {result.breakdown.map((c) => {
                const ratio = c.max === 0 ? 1 : c.earned / c.max
                const Icon = ratio >= 0.999 ? CheckCircle2 : AlertCircle
                const iconColor = ratio >= 0.999 ? '#16a34a' : ratio >= 0.5 ? '#ca8a04' : '#dc2626'
                return (
                  <div key={c.key} style={{
                    display: 'flex', alignItems: 'flex-start', gap: 6, padding: '6px 0',
                    borderTop: '1px solid var(--gray-100)',
                  }}>
                    <Icon size={14} style={{ color: iconColor, flexShrink: 0, marginTop: 2 }} />
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8 }}>
                        <span style={{ fontWeight: 600, color: 'var(--gray-800)' }}>{c.label}</span>
                        <span style={{ color: 'var(--gray-500)' }}>{c.earned}/{c.max}</span>
                      </div>
                      <div style={{ color: 'var(--gray-600)' }}>{c.detail}</div>
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </>
      )}
    </div>
  )
}

function scoreBand(score: number | null): { label: string; color: string } {
  if (score === null) return { label: '—', color: 'var(--gray-400)' }
  if (score >= 85) return { label: 'Excellent', color: '#16a34a' }
  if (score >= 70) return { label: 'Good',      color: '#65a30d' }
  if (score >= 55) return { label: 'Needs work', color: '#ca8a04' }
  if (score >= 40) return { label: 'Weak',      color: '#ea580c' }
  return { label: 'Poor', color: '#dc2626' }
}

// =============================================================================
// Pre-publish QA panel (US-BLOG-040)
// =============================================================================

function QaPanel({
  qa, running, blocked, saving, onRerun, onForcePublish, onClose,
}: {
  qa: QaResult | null
  running: boolean
  blocked: boolean
  saving: boolean
  onRerun: () => void
  onForcePublish: () => void
  onClose: () => void
}) {
  const errors = qa?.checks.filter((c) => c.severity === 'error' && !c.passed) ?? []
  const warnings = qa?.checks.filter((c) => c.severity === 'warning' && !c.passed) ?? []
  const infos = qa?.checks.filter((c) => c.severity === 'info' && !c.passed) ?? []
  const passed = qa?.checks.filter((c) => c.passed) ?? []

  return (
    <div
      className="admin-ai-panel"
      style={blocked ? { borderColor: '#dc2626', borderWidth: 2 } : undefined}
    >
      <h3 style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <span>
          <ShieldCheck size={14} style={{ marginRight: 4, verticalAlign: 'middle' }} />
          Pre-publish QA
          {running && <span style={{ marginLeft: 8, fontSize: 11, color: 'var(--gray-500)' }}>checking…</span>}
        </span>
        <button
          type="button"
          onClick={onClose}
          style={{
            background: 'transparent', border: 'none', cursor: 'pointer',
            color: 'var(--gray-500)', fontSize: 11,
          }}
        >
          hide
        </button>
      </h3>

      {!qa && !running && (
        <div className="admin-help">Click "Run QA" to check this post against the publish checklist.</div>
      )}

      {qa && (
        <>
          <div style={{
            display: 'flex', gap: 6, marginBottom: 10, fontSize: 12, fontWeight: 600,
          }}>
            <Pill count={errors.length}    color="#dc2626" label="errors"   />
            <Pill count={warnings.length}  color="#ca8a04" label="warnings" />
            <Pill count={infos.length}     color="#2563eb" label="info"     />
            <Pill count={passed.length}    color="#16a34a" label="passed"   />
          </div>

          {blocked && errors.length > 0 && (
            <div style={{
              background: '#fef2f2', border: '1px solid #fecaca', borderRadius: 6,
              padding: 10, marginBottom: 10, fontSize: 12, color: '#991b1b',
            }}>
              <div style={{ fontWeight: 600, marginBottom: 4 }}>Publish blocked</div>
              Fix the {errors.length} error{errors.length === 1 ? '' : 's'} below, or override.
              <button
                type="button"
                onClick={onForcePublish}
                disabled={saving}
                style={{
                  marginTop: 8, padding: '6px 10px', fontSize: 12, fontWeight: 600,
                  background: '#dc2626', color: 'white', border: 'none', borderRadius: 4,
                  cursor: saving ? 'not-allowed' : 'pointer', width: '100%',
                }}
              >
                {saving ? 'Publishing…' : 'Publish anyway (override)'}
              </button>
            </div>
          )}

          {errors.length === 0 && qa.canPublish && (
            <div style={{
              background: '#f0fdf4', border: '1px solid #bbf7d0', borderRadius: 6,
              padding: 10, marginBottom: 10, fontSize: 12, color: '#166534',
              display: 'flex', alignItems: 'center', gap: 6,
            }}>
              <CheckCircle2 size={14} />
              All errors clear — safe to publish.
            </div>
          )}

          <div style={{ fontSize: 12 }}>
            <CheckGroup title="Errors" checks={errors} icon={AlertCircle} iconColor="#dc2626" />
            <CheckGroup title="Warnings" checks={warnings} icon={AlertCircle} iconColor="#ca8a04" />
            <CheckGroup title="Info" checks={infos} icon={Info} iconColor="#2563eb" />
            <details style={{ marginTop: 8 }}>
              <summary style={{ cursor: 'pointer', fontSize: 11, color: 'var(--gray-600)' }}>
                {passed.length} passed
              </summary>
              <CheckGroup title="" checks={passed} icon={CheckCircle2} iconColor="#16a34a" passed />
            </details>
          </div>

          <button
            type="button"
            onClick={onRerun}
            disabled={running}
            style={{
              width: '100%', marginTop: 10, padding: '6px 10px', fontSize: 12,
              background: 'transparent', border: '1px solid var(--gray-200)',
              borderRadius: 4, cursor: 'pointer', color: 'var(--gray-700)',
            }}
          >
            {running ? 'Re-running…' : 'Re-run QA'}
          </button>
        </>
      )}
    </div>
  )
}

function Pill({ count, color, label }: { count: number; color: string; label: string }) {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 4,
      padding: '2px 8px', borderRadius: 10, fontSize: 11,
      background: count > 0 ? color : 'var(--gray-100)',
      color: count > 0 ? 'white' : 'var(--gray-500)',
    }}>
      {count} {label}
    </span>
  )
}

function CheckGroup({
  title, checks, icon: Icon, iconColor, passed = false,
}: {
  title: string
  checks: QaResult['checks']
  icon: typeof AlertCircle
  iconColor: string
  passed?: boolean
}) {
  if (checks.length === 0) return null
  return (
    <div style={{ marginBottom: title ? 10 : 0 }}>
      {title && <div style={{ fontWeight: 600, color: 'var(--gray-700)', marginBottom: 4 }}>{title}</div>}
      {checks.map((c) => (
        <div key={c.id} style={{
          display: 'flex', alignItems: 'flex-start', gap: 6,
          padding: '6px 0', borderTop: '1px solid var(--gray-100)',
          opacity: passed ? 0.8 : 1,
        }}>
          <Icon size={14} style={{ color: iconColor, flexShrink: 0, marginTop: 2 }} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontWeight: 500, color: 'var(--gray-800)' }}>{c.label}</div>
            <div style={{ color: 'var(--gray-600)' }}>{c.message}</div>
            {!!c.details && typeof c.details === 'object' && (
              <QaDetails details={c.details as Record<string, unknown>} />
            )}
          </div>
        </div>
      ))}
    </div>
  )
}

// =============================================================================
// AI critique log panel (US-BLOG-039)
// =============================================================================

interface CritiqueIssueLite {
  severity: 'blocker' | 'major' | 'minor'
  area: string
  message: string
  location?: string
  suggested_fix: string
}

interface CritiqueIterationLite {
  iteration: number
  score: number
  summary: string
  should_continue: boolean
  revised: boolean
  issues: CritiqueIssueLite[]
  input_tokens?: number
  output_tokens?: number
}

interface CritiqueLogLite {
  iterations: CritiqueIterationLite[]
  stopped_reason?: string
  revisions?: number
}

function readCritiqueLog(aiMeta: unknown): CritiqueLogLite | null {
  if (!aiMeta || typeof aiMeta !== 'object') return null
  const m = aiMeta as Record<string, unknown>
  const log = m.critique_log
  if (!log || typeof log !== 'object') return null
  const iters = (log as Record<string, unknown>).iterations
  if (!Array.isArray(iters) || iters.length === 0) return null
  return log as unknown as CritiqueLogLite
}

function CritiqueLogPanel({ aiMeta }: { aiMeta: unknown }) {
  const log = readCritiqueLog(aiMeta)
  if (!log) return null

  return (
    <div className="admin-ai-panel">
      <h3>
        <MessageSquare size={14} style={{ marginRight: 4, verticalAlign: 'middle' }} />
        AI critique log
      </h3>
      <div style={{ fontSize: 12, color: 'var(--gray-600)', marginBottom: 8 }}>
        {log.iterations.length} iteration{log.iterations.length === 1 ? '' : 's'}
        {log.stopped_reason && <> — stopped: <code style={{ fontSize: 11 }}>{log.stopped_reason}</code></>}
      </div>

      {log.iterations.map((it) => (
        <details key={it.iteration} style={{ marginBottom: 8, fontSize: 12 }}>
          <summary style={{ cursor: 'pointer', fontWeight: 600 }}>
            Iteration {it.iteration} — score {it.score}/100
            {it.revised && <span style={{ marginLeft: 6, color: 'var(--gray-500)', fontWeight: 400 }}>(revised after)</span>}
          </summary>
          <div style={{ paddingTop: 6 }}>
            <div style={{ color: 'var(--gray-700)', marginBottom: 6 }}>{it.summary}</div>
            {it.issues.length === 0 ? (
              <div style={{ color: 'var(--gray-500)', fontStyle: 'italic' }}>No issues flagged.</div>
            ) : (
              <ul style={{ paddingLeft: 18, margin: 0 }}>
                {it.issues.map((iss, i) => (
                  <li key={i} style={{ marginBottom: 4 }}>
                    <span style={severityStyle(iss.severity)}>{iss.severity}</span>{' '}
                    <span style={{ color: 'var(--gray-500)' }}>· {iss.area}</span>
                    <div style={{ color: 'var(--gray-800)' }}>{iss.message}</div>
                    {iss.location && <div style={{ color: 'var(--gray-500)' }}>at: {iss.location}</div>}
                    <div style={{ color: 'var(--gray-700)' }}><em>Fix:</em> {iss.suggested_fix}</div>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </details>
      ))}
    </div>
  )
}

// =============================================================================
// Syndicate dialog (US-BLOG-044/045/046/048)
// =============================================================================

const SYNDICATE_PLATFORMS: Array<{ id: SyndicationPlatform; label: string; subtitle: string }> = [
  { id: 'x',         label: 'X (Twitter)', subtitle: 'Hook + 6–11 tweet thread + CTA tweet' },
  { id: 'linkedin',  label: 'LinkedIn',    subtitle: 'Long-form post, link in first comment, 3–5 hashtags' },
  { id: 'facebook',  label: 'Facebook',    subtitle: '≤300 char copy + link' },
  { id: 'pinterest', label: 'Pinterest',   subtitle: '3 pin copy variants (title + description)' },
]

function SyndicateDialog({
  platforms, onChangePlatforms, syndicating, message, onClose, onConfirm,
}: {
  platforms: SyndicationPlatform[]
  onChangePlatforms: (next: SyndicationPlatform[]) => void
  syndicating: boolean
  message: string | null
  onClose: () => void
  onConfirm: () => void
}) {
  const toggle = (id: SyndicationPlatform) => {
    if (platforms.includes(id)) onChangePlatforms(platforms.filter((p) => p !== id))
    else onChangePlatforms([...platforms, id])
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      style={{
        position: 'fixed', inset: 0, background: 'rgba(15,23,42,0.55)',
        display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 50,
      }}
      onClick={onClose}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          background: 'white', borderRadius: 8, padding: 20, width: 'min(540px, 92vw)',
          maxHeight: '88vh', overflowY: 'auto', boxShadow: '0 20px 50px rgba(0,0,0,0.25)',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
          <Share2 size={18} />
          <h3 style={{ margin: 0 }}>Syndicate to socials</h3>
        </div>
        <div style={{ fontSize: 13, color: 'var(--gray-600)', marginBottom: 16 }}>
          AI generates platform-native copy and saves each variant as a <strong>draft</strong> in the social posts list.
          You review before publishing — Make.com handles the actual posting.
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginBottom: 16 }}>
          {SYNDICATE_PLATFORMS.map((p) => {
            const checked = platforms.includes(p.id)
            return (
              <label
                key={p.id}
                style={{
                  display: 'flex', alignItems: 'flex-start', gap: 10, padding: 10,
                  border: '1px solid', borderColor: checked ? '#16a34a' : 'var(--gray-200)',
                  borderRadius: 6, cursor: 'pointer',
                  background: checked ? '#f0fdf4' : 'white',
                }}
              >
                <input
                  type="checkbox"
                  checked={checked}
                  onChange={() => toggle(p.id)}
                  style={{ marginTop: 3 }}
                  disabled={syndicating}
                />
                <div>
                  <div style={{ fontWeight: 600 }}>{p.label}</div>
                  <div style={{ fontSize: 12, color: 'var(--gray-600)' }}>{p.subtitle}</div>
                </div>
              </label>
            )
          })}
        </div>

        {message && (
          <div className="admin-error" style={{ marginBottom: 12 }}>{message}</div>
        )}

        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8 }}>
          <button
            type="button"
            className="admin-btn admin-btn-secondary"
            onClick={onClose}
            disabled={syndicating}
          >
            Cancel
          </button>
          <button
            type="button"
            className="admin-btn admin-btn-primary"
            onClick={onConfirm}
            disabled={syndicating || platforms.length === 0}
          >
            {syndicating ? 'Generating…' : `Generate ${platforms.length} variant${platforms.length === 1 ? '' : 's'}`}
          </button>
        </div>
      </div>
    </div>
  )
}

function severityStyle(severity: string): CSSProperties {
  const color =
    severity === 'blocker' ? '#dc2626' :
    severity === 'major'   ? '#ca8a04' :
                             '#2563eb'
  return {
    display: 'inline-block', padding: '0 6px', borderRadius: 8,
    background: color, color: 'white', fontSize: 10, fontWeight: 700,
    textTransform: 'uppercase', letterSpacing: 0.3,
  }
}

function QaDetails({ details }: { details: Record<string, unknown> }) {
  if (Array.isArray(details.broken)) {
    return (
      <ul style={{ paddingLeft: 18, margin: '4px 0 0', color: 'var(--gray-700)' }}>
        {(details.broken as Array<{ href: string; reason: string }>).map((b, i) => (
          <li key={i}><code style={{ fontSize: 11 }}>{b.href}</code> — {b.reason}</li>
        ))}
      </ul>
    )
  }
  if (Array.isArray(details.missingAlt)) {
    return (
      <ul style={{ paddingLeft: 18, margin: '4px 0 0', color: 'var(--gray-700)' }}>
        {(details.missingAlt as string[]).map((src, i) => (
          <li key={i}><code style={{ fontSize: 11 }}>{src}</code></li>
        ))}
      </ul>
    )
  }
  if (Array.isArray(details.weak)) {
    return (
      <ul style={{ paddingLeft: 18, margin: '4px 0 0', color: 'var(--gray-700)' }}>
        {(details.weak as Array<{ href: string; anchor: string }>).map((w, i) => (
          <li key={i}>
            <code style={{ fontSize: 11 }}>{w.anchor}</code> → <code style={{ fontSize: 11 }}>{w.href}</code>
          </li>
        ))}
      </ul>
    )
  }
  return null
}
