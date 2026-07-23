import SEO from '../components/SEO'
import './Legal.css'

export default function Cookies() {
  return (
    <div className="legal-page">
      <SEO
        title="Cookie Notice"
        description="How Daily OK uses (and does not use) cookies and similar technologies on our website and apps."
        path="/cookies"
      />
      <div className="container">
        <div className="legal-content">
          <h1>Cookie Notice</h1>
          <p className="legal-updated">Last updated: July 23, 2026</p>

          <section>
            <h2>Overview</h2>
            <p>
              Daily OK is built around the principle of data minimization. We do not use
              advertising cookies or third-party marketing pixels on our website
              (dailyok.net) or in our mobile apps. The only cookies that are not strictly
              necessary are the optional analytics cookies described below, which are set
              only if you consent.
            </p>
          </section>

          <section>
            <h2>What Are Cookies?</h2>
            <p>
              Cookies are small text files stored on your device when you visit a website.
              "Similar technologies" include local storage, session storage, and SDK
              identifiers used by mobile apps to remember preferences or device state.
            </p>
          </section>

          <section>
            <h2>Categories We Use</h2>
            <h3>Strictly Necessary</h3>
            <p>
              We use a limited amount of browser storage (session storage and local storage)
              to keep the website functional — for example, to remember your navigation
              state, your accessibility preferences (such as reduced motion), and to load
              pages efficiently. These technologies are required for the site to operate and
              cannot be turned off without breaking the site.
            </p>

            <h3>Privacy-First Analytics (No Cookies)</h3>
            <p>
              We use Cloudflare Web Analytics to count page views and understand which pages
              are popular. Cloudflare Web Analytics{' '}
              <strong>does not set cookies, does not use fingerprinting, and does not
              collect personally identifiable information.</strong> Because no cookies or
              persistent identifiers are set, it runs without a consent prompt under the EU
              ePrivacy Directive or comparable laws.
            </p>

            <h3>Analytics Cookies (Optional — Only With Your Consent)</h3>
            <p>
              With your consent, we also use <strong>Google Analytics (GA4)</strong>,
              provided by Google LLC, to understand how visitors use the site so we can
              improve it. Google Analytics sets first-party cookies (such as{' '}
              <code>_ga</code>) and transfers data to Google. We enable IP anonymization and
              do not use Google Analytics for advertising.
            </p>
            <p>
              Google Analytics is <strong>off by default</strong>. When you first visit the
              site we show a consent banner; Google Analytics is only loaded if you choose{' '}
              <em>Accept analytics</em>. If you decline — or if your browser sends a Global
              Privacy Control (GPC) signal — Google Analytics is never loaded. You can change
              your mind at any time by clearing this site's browser storage, which resets the
              banner so you can choose again.
            </p>

            <h3>Categories We Do Not Use</h3>
            <ul>
              <li>Advertising or remarketing cookies</li>
              <li>Cross-site tracking pixels (Facebook Pixel, Google Ads, etc.)</li>
              <li>Third-party social-media share buttons that load tracking scripts</li>
              <li>Session-replay tools (heatmaps or mouse-movement recording)</li>
            </ul>
          </section>

          <section>
            <h2>Mobile Apps</h2>
            <p>
              The Daily OK iOS and Android apps do not use the IDFA (Identifier for
              Advertisers) or the Android Advertising ID. We do not integrate any
              advertising or attribution SDKs. The apps use a push-notification token (APNs
              on iOS, FCM on Android) solely to deliver check-in and escalation
              notifications, as described in our <a href="/privacy">Privacy Policy</a>.
            </p>
          </section>

          <section>
            <h2>Managing Browser Storage</h2>
            <p>
              You can clear cookies and other browser storage at any time from your browser
              settings. Doing so will not affect your account but may reset preferences such
              as accessibility settings on the website.
            </p>
          </section>

          <section>
            <h2>Changes to This Notice</h2>
            <p>
              If we introduce a new technology that requires consent, we will update this
              notice and present it in the consent banner before the technology is loaded, so
              you can accept or decline. Any change will be reflected in the "Last updated"
              date above.
            </p>
          </section>

          <section>
            <h2>Contact</h2>
            <p>
              Questions about this Notice? Email{' '}
              <a href="mailto:privacy@dailyok.net">privacy@dailyok.net</a>.
            </p>
          </section>
        </div>
      </div>
    </div>
  )
}
