import { useEffect, useState, type FormEvent } from 'react'
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
  Sparkles, Save,
} from 'lucide-react'
import {
  createPost, updatePost, getPost, generateArticle, generateSeoMeta, improveText,
  type BlogPost,
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

  const save = async (e: FormEvent | null, overrides: Partial<Draft> = {}) => {
    e?.preventDefault()
    setSaving(true)
    setError(null)
    setSuccess(null)
    try {
      const payload = { ...draft, ...overrides }
      if (mode === 'new' || !postId) {
        const res = await createPost({
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
        })
        setPostId(res.post.id)
        setDraft((d) => ({ ...d, slug: res.post.slug, status: res.post.status, ...overrides }))
        setSuccess('Created')
        navigate(`/admin/blog/${res.post.id}`, { replace: true })
      } else {
        const res = await updatePost(postId, {
          title: payload.title,
          slug: payload.slug,
          excerpt: payload.excerpt || null,
          content_html: payload.content_html,
          featured_image_url: payload.featured_image_url || null,
          seo_title: payload.seo_title || null,
          seo_description: payload.seo_description || null,
          tags: payload.tags,
          category: payload.category || null,
          status: payload.status,
        })
        setDraft((d) => ({ ...d, slug: res.post.slug, status: res.post.status, ...overrides }))
        setSuccess('Saved')
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save')
    } finally {
      setSaving(false)
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

        <div>
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
        </div>
      </div>
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
