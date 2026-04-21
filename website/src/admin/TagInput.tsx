import { useState, type KeyboardEvent } from 'react'

export function TagInput({
  tags,
  onChange,
  placeholder = 'Type a tag and press Enter',
}: {
  tags: string[]
  onChange: (tags: string[]) => void
  placeholder?: string
}) {
  const [value, setValue] = useState('')

  const addTag = (raw: string) => {
    const tag = raw.trim().toLowerCase()
    if (!tag) return
    if (tags.includes(tag)) return
    onChange([...tags, tag])
  }

  const remove = (tag: string) => onChange(tags.filter((t) => t !== tag))

  const onKey = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter' || e.key === ',') {
      e.preventDefault()
      addTag(value)
      setValue('')
    } else if (e.key === 'Backspace' && value === '' && tags.length > 0) {
      remove(tags[tags.length - 1])
    }
  }

  return (
    <div className="admin-tags">
      {tags.map((t) => (
        <span key={t} className="admin-tag">
          {t}
          <button type="button" onClick={() => remove(t)} aria-label={`Remove ${t}`}>×</button>
        </span>
      ))}
      <input
        type="text"
        value={value}
        onChange={(e) => setValue(e.target.value)}
        onKeyDown={onKey}
        onBlur={() => {
          if (value) { addTag(value); setValue('') }
        }}
        placeholder={tags.length === 0 ? placeholder : ''}
      />
    </div>
  )
}
