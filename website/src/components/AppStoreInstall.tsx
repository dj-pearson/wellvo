import { APP_STORE_URL } from '../lib/appStore'
import { trackEvent } from '../utils/analytics'

/**
 * Desktop install path: an App Store badge plus a QR code that opens the same
 * listing on the visitor's iPhone. Many buyers are adult children browsing on
 * a laptop, where a plain "Download" link just opens the App Store web page.
 *
 * Shown only at min-width 769px (see .app-install in shared.css) — on a phone
 * the page's own App Store buttons already are the install path. The badge is
 * drawn here rather than hotlinked from Apple; the QR is a static SVG written
 * by scripts/generate-app-store-qr.mjs from APP_STORE_URL.
 */
export default function AppStoreInstall({ className = '' }: { className?: string }) {
  return (
    <div className={`app-install ${className}`.trim()}>
      <img
        className="app-install-qr"
        src="/app-store-qr.svg"
        alt="QR code that opens Daily OK on the App Store"
        width={96}
        height={96}
        loading="lazy"
        decoding="async"
      />
      <div className="app-install-text">
        <p>Scan with your iPhone camera to get Daily OK, or</p>
        <a
          href={APP_STORE_URL}
          className="app-store-badge"
          target="_blank"
          rel="noopener noreferrer"
          onClick={() => trackEvent('download_cta_click')}
        >
          <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" focusable="false">
            <path
              fill="currentColor"
              d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701"
            />
          </svg>
          <span className="app-store-badge-text">
            <span className="app-store-badge-small">Download on the</span>{' '}
            <span className="app-store-badge-large">App Store</span>
          </span>
        </a>
      </div>
    </div>
  )
}
