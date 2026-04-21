import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { Plus, Trash2, Edit3, Sparkles, Play } from 'lucide-react'
import {
  listTemplates, saveTemplate, deleteTemplate, batchGenerate, generateFromTemplate,
  type BlogTemplate,
} from '../lib/admin'
import { TagInput } from './TagInput'
import './admin.css'

export default function AdminBlogTemplates() {
  const [templates, setTemplates] = useState<BlogTemplate[]>([])
  const [editing, setEditing] = useState<Partial<BlogTemplate> | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const refresh = async () => {
    setLoading(true)
    try {
      const res = await listTemplates()
      setTemplates(res.templates)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { void refresh() }, [])

  return (
    <>
      <div className="admin-page-header">
        <div>
          <div className="admin-page-title">pSEO templates</div>
          <div className="admin-page-subtitle">
            Reusable AI prompts for programmatic SEO — scaffolds for bulk article generation
          </div>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <Link to="/admin/blog" className="admin-btn admin-btn-secondary">Back to posts</Link>
          <button
            className="admin-btn admin-btn-primary"
            onClick={() =>
              setEditing({
                name: '',
                description: '',
                system_prompt: '',
                user_prompt_template: '',
                default_tags: [],
                default_category: '',
                slug_template: '',
                title_template: '',
              })
            }
          >
            <Plus size={14} /> New template
          </button>
        </div>
      </div>

      {error && <div className="admin-error">{error}</div>}

      <div style={{ display: 'grid', gap: 16, gridTemplateColumns: editing ? '1fr 1fr' : '1fr' }}>
        <div>
          {loading && <div className="admin-empty">Loading…</div>}
          {!loading && templates.length === 0 && (
            <div className="admin-empty">No templates yet. Create one to run AI batch generations.</div>
          )}
          <div style={{ display: 'grid', gap: 12 }}>
            {templates.map((t) => (
              <div key={t.id} className="admin-card">
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'start', gap: 12 }}>
                  <div style={{ flex: 1 }}>
                    <div className="admin-card-title">{t.name}</div>
                    {t.description && (
                      <div style={{ fontSize: 13, color: 'var(--gray-600)', marginBottom: 8 }}>{t.description}</div>
                    )}
                    <div style={{ fontSize: 12, color: 'var(--gray-500)' }}>
                      Variables: {extractVariables(t.user_prompt_template).map((v) => (
                        <code key={v} style={{ marginRight: 6 }}>{`{{${v}}}`}</code>
                      ))}
                    </div>
                  </div>
                  <div style={{ display: 'flex', gap: 6 }}>
                    <button className="admin-btn admin-btn-sm admin-btn-secondary" onClick={() => setEditing(t)}>
                      <Edit3 size={12} /> Edit
                    </button>
                    <button
                      className="admin-btn admin-btn-sm admin-btn-danger"
                      onClick={async () => {
                        if (!confirm(`Delete template "${t.name}"?`)) return
                        await deleteTemplate(t.id)
                        void refresh()
                      }}
                    >
                      <Trash2 size={12} />
                    </button>
                  </div>
                </div>

                <RunTemplate template={t} onRun={() => void refresh()} />
              </div>
            ))}
          </div>
        </div>

        {editing && (
          <div>
            <TemplateEditor
              template={editing}
              onCancel={() => setEditing(null)}
              onSaved={() => {
                setEditing(null)
                void refresh()
              }}
            />
          </div>
        )}
      </div>
    </>
  )
}

function extractVariables(template: string): string[] {
  const matches = template.matchAll(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g)
  const set = new Set<string>()
  for (const m of matches) set.add(m[1])
  return [...set]
}

function TemplateEditor({
  template,
  onCancel,
  onSaved,
}: {
  template: Partial<BlogTemplate>
  onCancel: () => void
  onSaved: () => void
}) {
  const [form, setForm] = useState<Partial<BlogTemplate>>(template)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.name || !form.system_prompt || !form.user_prompt_template) {
      setError('Name, system prompt, and user prompt template are required')
      return
    }
    setSaving(true)
    setError(null)
    try {
      await saveTemplate({
        id: form.id,
        name: form.name,
        description: form.description ?? '',
        system_prompt: form.system_prompt,
        user_prompt_template: form.user_prompt_template,
        slug_template: form.slug_template ?? '',
        title_template: form.title_template ?? '',
        default_tags: form.default_tags ?? [],
        default_category: form.default_category ?? '',
      })
      onSaved()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save')
    } finally {
      setSaving(false)
    }
  }

  return (
    <form className="admin-card admin-form" onSubmit={submit}>
      <div className="admin-card-title">{form.id ? 'Edit template' : 'New template'}</div>
      {error && <div className="admin-error">{error}</div>}

      <div>
        <label className="admin-label">Name</label>
        <input className="admin-input" value={form.name ?? ''} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
      </div>
      <div>
        <label className="admin-label">Description</label>
        <input className="admin-input" value={form.description ?? ''} onChange={(e) => setForm({ ...form, description: e.target.value })} />
      </div>
      <div>
        <label className="admin-label">System prompt <span className="admin-help">(cached across batch runs)</span></label>
        <textarea
          className="admin-textarea"
          style={{ minHeight: 160 }}
          value={form.system_prompt ?? ''}
          onChange={(e) => setForm({ ...form, system_prompt: e.target.value })}
          placeholder="The persona and output contract (e.g. JSON schema) that the AI must follow."
          required
        />
      </div>
      <div>
        <label className="admin-label">
          User prompt template <span className="admin-help">(use {'{{variable}}'} placeholders)</span>
        </label>
        <textarea
          className="admin-textarea"
          style={{ minHeight: 120 }}
          value={form.user_prompt_template ?? ''}
          onChange={(e) => setForm({ ...form, user_prompt_template: e.target.value })}
          placeholder={`e.g. Write an article about "{{keyword}}" for {{audience}}.`}
          required
        />
      </div>
      <div className="admin-form-row">
        <div>
          <label className="admin-label">Slug template</label>
          <input
            className="admin-input"
            value={form.slug_template ?? ''}
            onChange={(e) => setForm({ ...form, slug_template: e.target.value })}
            placeholder="{{keyword}}-guide"
          />
        </div>
        <div>
          <label className="admin-label">Title template</label>
          <input
            className="admin-input"
            value={form.title_template ?? ''}
            onChange={(e) => setForm({ ...form, title_template: e.target.value })}
            placeholder="{{keyword}} — a practical guide"
          />
        </div>
      </div>
      <div className="admin-form-row">
        <div>
          <label className="admin-label">Default category</label>
          <input
            className="admin-input"
            value={form.default_category ?? ''}
            onChange={(e) => setForm({ ...form, default_category: e.target.value })}
          />
        </div>
        <div>
          <label className="admin-label">Default tags</label>
          <TagInput tags={form.default_tags ?? []} onChange={(tags) => setForm({ ...form, default_tags: tags })} />
        </div>
      </div>

      <div style={{ display: 'flex', gap: 8 }}>
        <button type="submit" className="admin-btn admin-btn-primary" disabled={saving}>
          {saving ? 'Saving…' : 'Save template'}
        </button>
        <button type="button" className="admin-btn admin-btn-secondary" onClick={onCancel}>Cancel</button>
      </div>
    </form>
  )
}

function RunTemplate({ template, onRun }: { template: BlogTemplate; onRun: () => void }) {
  const [showRunner, setShowRunner] = useState(false)
  const [singleVars, setSingleVars] = useState<Record<string, string>>({})
  const [batchRaw, setBatchRaw] = useState('')
  const [working, setWorking] = useState(false)
  const [result, setResult] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const variables = extractVariables(template.user_prompt_template)

  const runSingle = async () => {
    setWorking(true)
    setError(null)
    setResult(null)
    try {
      const res = await generateFromTemplate({
        template_id: template.id,
        variables: singleVars,
        save_as_draft: true,
      })
      setResult(`Created draft: ${res.post?.slug ?? res.article.slug}`)
      onRun()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed')
    } finally {
      setWorking(false)
    }
  }

  const runBatch = async () => {
    const rows = parseBatch(batchRaw, variables)
    if (!rows.ok) {
      setError(rows.error)
      return
    }
    if (rows.rows.length === 0) {
      setError('No rows parsed')
      return
    }
    if (!confirm(`Generate ${rows.rows.length} drafts? This will consume AI tokens.`)) return
    setWorking(true)
    setError(null)
    setResult(null)
    try {
      const res = await batchGenerate({ template_id: template.id, batch: rows.rows })
      const succeeded = res.results.filter((r) => r.post_id).length
      setResult(`Batch done — ${succeeded} drafts created, ${res.results.length - succeeded} failed`)
      onRun()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed')
    } finally {
      setWorking(false)
    }
  }

  if (!showRunner) {
    return (
      <div style={{ marginTop: 12, borderTop: '1px solid var(--gray-100)', paddingTop: 12 }}>
        <button className="admin-btn admin-btn-sm admin-btn-secondary" onClick={() => setShowRunner(true)}>
          <Play size={12} /> Run
        </button>
      </div>
    )
  }

  return (
    <div style={{ marginTop: 12, borderTop: '1px solid var(--gray-100)', paddingTop: 12 }}>
      {error && <div className="admin-error">{error}</div>}
      {result && <div className="admin-success">{result}</div>}

      <div style={{ display: 'grid', gap: 8 }}>
        <strong style={{ fontSize: 13 }}>Single run — fill variables:</strong>
        {variables.map((v) => (
          <div key={v}>
            <label className="admin-label">{v}</label>
            <input
              className="admin-input"
              value={singleVars[v] ?? ''}
              onChange={(e) => setSingleVars({ ...singleVars, [v]: e.target.value })}
            />
          </div>
        ))}
        <button
          className="admin-btn admin-btn-primary admin-btn-sm"
          onClick={runSingle}
          disabled={working || variables.some((v) => !singleVars[v])}
        >
          <Sparkles size={12} /> {working ? 'Generating…' : 'Generate draft'}
        </button>

        <div style={{ borderTop: '1px solid var(--gray-100)', paddingTop: 10, marginTop: 8 }}>
          <strong style={{ fontSize: 13 }}>Or batch (max 25) — CSV with header row:</strong>
          <div className="admin-help">
            First line: <code>{variables.join(',')}</code>. One row per article.
          </div>
          <textarea
            className="admin-textarea"
            style={{ marginTop: 6, fontFamily: 'monospace', fontSize: 12 }}
            rows={6}
            value={batchRaw}
            onChange={(e) => setBatchRaw(e.target.value)}
            placeholder={`${variables.join(',')}\nvalue1,value2\n…`}
          />
          <button
            className="admin-btn admin-btn-primary admin-btn-sm"
            onClick={runBatch}
            disabled={working || !batchRaw.trim()}
            style={{ marginTop: 6 }}
          >
            <Sparkles size={12} /> {working ? 'Running…' : 'Run batch'}
          </button>
        </div>

        <button className="admin-btn admin-btn-sm admin-btn-secondary" onClick={() => setShowRunner(false)}>Close</button>
      </div>
    </div>
  )
}

function parseBatch(
  raw: string,
  expectedVars: string[],
): { ok: true; rows: Array<Record<string, string>> } | { ok: false; error: string } {
  const lines = raw.split(/\r?\n/).map((l) => l.trim()).filter(Boolean)
  if (lines.length < 2) return { ok: false, error: 'Need a header row and at least one data row' }
  const header = splitCsv(lines[0])
  const missing = expectedVars.filter((v) => !header.includes(v))
  if (missing.length) return { ok: false, error: `Missing columns: ${missing.join(', ')}` }

  const rows: Array<Record<string, string>> = []
  for (let i = 1; i < lines.length; i++) {
    const cols = splitCsv(lines[i])
    if (cols.length !== header.length) {
      return { ok: false, error: `Row ${i + 1} has ${cols.length} cols, expected ${header.length}` }
    }
    const row: Record<string, string> = {}
    header.forEach((h, idx) => { row[h] = cols[idx] })
    rows.push(row)
  }
  return { ok: true, rows }
}

function splitCsv(line: string): string[] {
  const out: string[] = []
  let cur = ''
  let inQ = false
  for (let i = 0; i < line.length; i++) {
    const ch = line[i]
    if (inQ) {
      if (ch === '"' && line[i + 1] === '"') { cur += '"'; i++ }
      else if (ch === '"') { inQ = false }
      else { cur += ch }
    } else {
      if (ch === ',') { out.push(cur.trim()); cur = '' }
      else if (ch === '"') { inQ = true }
      else { cur += ch }
    }
  }
  out.push(cur.trim())
  return out
}
