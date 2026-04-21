import { useEffect, useState } from 'react'
import { loadMetrics, type DashboardMetrics, type DailyPoint } from '../lib/admin'
import './admin.css'

export default function AdminDashboard() {
  const [metrics, setMetrics] = useState<DashboardMetrics | null>(null)
  const [series, setSeries] = useState<DailyPoint[]>([])
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancelled = false
    loadMetrics(30)
      .then((res) => {
        if (cancelled) return
        setMetrics(res.metrics)
        setSeries(res.timeseries)
      })
      .catch((err) => {
        if (cancelled) return
        setError(err instanceof Error ? err.message : 'Failed to load metrics')
      })
      .finally(() => {
        if (cancelled) return
        setLoading(false)
      })
    return () => { cancelled = true }
  }, [])

  return (
    <>
      <div className="admin-page-header">
        <div>
          <div className="admin-page-title">Overview</div>
          <div className="admin-page-subtitle">System health and activity at a glance</div>
        </div>
      </div>

      {error && <div className="admin-error">{error}</div>}
      {loading && <div className="admin-empty">Loading metrics…</div>}

      {metrics && (
        <>
          <div className="admin-stats">
            <Stat label="Total users" value={metrics.total_users} />
            <Stat label="Families" value={metrics.total_families} />
            <Stat label="Active members" value={metrics.total_members} />
            <Stat label="Paid families" value={metrics.paid_families} delta={`${metrics.free_families} on free`} />
            <Stat label="Check-ins today" value={metrics.checkins_today} />
            <Stat label="Check-ins (7d)" value={metrics.checkins_7d} />
            <Stat label="Missed (7d)" value={metrics.missed_requests_7d} />
            <Stat label="New users (7d)" value={metrics.new_users_7d} delta={`${metrics.new_users_30d} in 30d`} />
            <Stat label="Pending requests" value={metrics.pending_requests} />
            <Stat label="Blog posts" value={metrics.published_posts} delta={`${metrics.draft_posts} drafts`} />
            <Stat label="Social scheduled" value={metrics.social_posts_scheduled} delta={`${metrics.social_posts_posted_7d} posted (7d)`} />
          </div>

          {series.length > 0 && (
            <>
              <DailyChart label="New users" data={series.map((p) => ({ day: p.day, value: p.new_users }))} />
              <DailyChart label="Check-ins" data={series.map((p) => ({ day: p.day, value: p.checkins }))} />
              <DailyChart label="Missed" data={series.map((p) => ({ day: p.day, value: p.missed }))} accent="#ef4444" />
            </>
          )}
        </>
      )}
    </>
  )
}

function Stat({ label, value, delta }: { label: string; value: number; delta?: string }) {
  return (
    <div className="admin-stat">
      <div className="admin-stat-label">{label}</div>
      <div className="admin-stat-value">{value.toLocaleString()}</div>
      {delta && <div className="admin-stat-delta">{delta}</div>}
    </div>
  )
}

function DailyChart({
  label,
  data,
  accent = 'var(--green-500)',
}: {
  label: string
  data: Array<{ day: string; value: number }>
  accent?: string
}) {
  const max = Math.max(1, ...data.map((d) => d.value))
  return (
    <div className="admin-card">
      <div className="admin-card-title">{label} — last {data.length} days</div>
      <div className="admin-chart">
        {data.map((d) => {
          const pct = (d.value / max) * 100
          const shortDay = d.day.slice(5) // MM-DD
          return (
            <div className="admin-chart-row" key={d.day}>
              <span>{shortDay}</span>
              <div className="admin-chart-bar-bg">
                <div className="admin-chart-bar" style={{ width: `${pct}%`, background: accent }} />
              </div>
              <span style={{ textAlign: 'right' }}>{d.value}</span>
            </div>
          )
        })}
      </div>
    </div>
  )
}
