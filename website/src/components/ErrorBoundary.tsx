import { Component, type ReactNode } from 'react'
import { captureError } from '../lib/sentry'

interface Props {
  children: ReactNode
}

interface State {
  hasError: boolean
}

function isStaleChunkError(error: Error): boolean {
  const msg = error?.message || ''
  return (
    /Failed to fetch dynamically imported module/i.test(msg) ||
    /Loading chunk [\w-]+ failed/i.test(msg) ||
    /error loading dynamically imported module/i.test(msg) ||
    /Importing a module script failed/i.test(msg)
  )
}

export default class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props)
    this.state = { hasError: false }
  }

  static getDerivedStateFromError(error: Error): State {
    // Stale chunk after a new deploy: the current HTML references a chunk hash
    // that no longer exists on the CDN, so the SPA fallback serves index.html
    // and the browser reports "MIME type text/html" for the .js module.
    // Reload once to pull the fresh index.html + new chunk hashes.
    if (isStaleChunkError(error)) {
      const key = 'chunk-reload-guard'
      const last = Number(sessionStorage.getItem(key) || '0')
      if (Date.now() - last > 30_000) {
        sessionStorage.setItem(key, String(Date.now()))
        window.location.reload()
      }
    }
    return { hasError: true }
  }

  componentDidCatch(error: Error, info: React.ErrorInfo): void {
    console.error('ErrorBoundary caught:', error, info.componentStack)
    // Report to Sentry unless it's a benign stale-chunk reload after a deploy.
    if (!isStaleChunkError(error)) {
      captureError(error, { componentStack: info.componentStack })
    }
  }

  render() {
    if (this.state.hasError) {
      return (
        <div style={{
          minHeight: '60vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '40px 24px',
          textAlign: 'center',
          fontFamily: "'Inter', system-ui, sans-serif",
        }}>
          <div>
            <h1 style={{ fontSize: 32, fontWeight: 700, color: '#111827', marginBottom: 12 }}>
              Something went wrong
            </h1>
            <p style={{ fontSize: 18, color: '#6b7280', marginBottom: 24 }}>
              An unexpected error occurred. Please try again.
            </p>
            <button
              onClick={() => {
                this.setState({ hasError: false })
                window.location.href = '/'
              }}
              style={{
                padding: '14px 28px',
                background: '#2ECC71',
                color: 'white',
                border: 'none',
                borderRadius: 12,
                fontSize: 16,
                fontWeight: 600,
                cursor: 'pointer',
              }}
            >
              Back to Home
            </button>
          </div>
        </div>
      )
    }

    return this.props.children
  }
}
