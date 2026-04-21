import { useEffect, useState } from 'react'
import { ExternalLink } from 'lucide-react'
import { loadMetrics, type DailyPoint, type DashboardMetrics } from '../lib/admin'
import './admin.css'

export default function AdminAnalytics() {
  const [metrics, setMetrics] = useState<DashboardMetrics | null>(null)
  const [series, setSeries] = useState<DailyPoint[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [days, setDays] = useState(30)

  const cfDashboardUrl = import.meta.env.VITE_CLOUDFLARE_ANALYTICS_URL as string | undefined

  useEffect(() => {
    setLoading(true)
    loadMetrics(days)
      .then((res) => {
        setMetrics(res.metrics)
        setSeries(res.timeseries)
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load'))
      .finally(() => setLoading(false))
  }, [days])

  return (
    <>
      <div className="admin-page-header">
        <div>
          <div className="admin-page-title">Analytics</div>
          <div className="admin-page-subtitle">Website traffic (via Cloudflare) and product activity</div>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          {[7, 30, 90].map((d) => (
            <button
              key={d}
              className={`admin-btn admin-btn-sm ${days === d ? 'admin-btn-primary' : 'admin-btn-secondary'}`}
              onClick={() => setDays(d)}
            >
              {d}d
            </button>
          ))}
        </div>
      </div>

      {error && <div className="admin-error">{error}</div>}

      <div className="admin-card">
        <div className="admin-card-title">Website traffic — Cloudflare Web Analytics</div>
        {cfDashboardUrl ? (
          <>
            <p style={{ fontSize: 14, color: 'var(--gray-600)', marginBottom: 12 }}>
              Cloudflare doesn't permit iframe embedding. Open the dashboard in a new tab.
            </p>
            <a
              href={cfDashboardUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="admin-btn admin-btn-primary"
            >
              <ExternalLink size={14} /> Open Cloudflare Analytics
            </a>
          </>
        ) : (
          <div style={{ fontSize: 14, color: 'var(--gray-600)' }}>
            Set <code>VITE_CLOUDFLARE_ANALYTICS_URL</code> to your Cloudflare Web Analytics dashboard URL
            to show a direct link here.
          </div>
        )}
      </div>

      {loading && <div className="admin-empty">Loading activity…</div>}

      {metrics && (
        <>
          <div className="admin-stats">
            <Stat label="Active subs" value={metrics.active_subscriptions} />
            <Stat label="Free families" value={metrics.free_families} />
            <Stat label="Check-ins today" value={metrics.checkins_today} />
            <Stat label={`Check-ins (${days}d)`} value={metrics.checkins_7d} />
            <Stat label={`New users (${days}d)`} value={metrics.new_users_7d} />
            <Stat label={`Missed (${days}d)`} value={metrics.missed_requests_7d} />
          </div>

          <Chart label={`Daily new users — last ${series.length} days`} series={series.map((p) => ({ day: p.day, value: p.new_users }))} />
          <Chart label={`Daily check-ins — last ${series.length} days`} series={series.map((p) => ({ day: p.day, value: p.checkins }))} />
          <Chart label={`Daily new families — last ${series.length} days`} series={series.map((p) => ({ day: p.day, value: p.new_families }))} />
          <Chart label={`Daily missed — last ${series.length} days`} series={series.map((p) => ({ day: p.day, value: p.missed }))} accent="#ef4444" />
        </>
      )}
    </>
  )
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="admin-stat">
      <div className="admin-stat-label">{label}</div>
      <div className="admin-stat-value">{value.toLocaleString()}</div>
    </div>
  )
}

function Chart({
  label,
  series,
  accent = 'var(--green-500)',
}: {
  label: string
  series: Array<{ day: string; value: number }>
  accent?: string
}) {
  const max = Math.max(1, ...series.map((d) => d.value))
  return (
    <div className="admin-card">
      <div className="admin-card-title">{label}</div>
      <div className="admin-chart">
        {series.map((d) => {
          const pct = (d.value / max) * 100
          return (
            <div className="admin-chart-row" key={d.day}>
              <span>{d.day.slice(5)}</span>
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
