import './Legal.css'
import './Accessibility.css'

export default function Accessibility() {
  return (
    <main className="legal-page">
      <div className="container">
        <div className="legal-content">
          <h1>Accessibility Statement</h1>
          <p className="legal-updated">Last updated: March 19, 2026</p>

          <section>
            <h2>Our Commitment</h2>
            <p>
              Wellvo is built for families, including aging adults who may rely on assistive
              technology. We are committed to making our app and website usable by everyone,
              regardless of ability or the device they use.
            </p>
          </section>

          <section>
            <h2>Supported Accessibility Features</h2>
            <p>We actively design and test for the following:</p>
            <ul className="accessibility-features">
              <li>
                <strong>VoiceOver and screen reader support</strong> — all interactive elements
                are labeled and navigable with VoiceOver on iOS and screen readers on the web.
              </li>
              <li>
                <strong>Voice Control compatibility</strong> — the app works with iOS Voice
                Control so users can navigate and check in hands-free.
              </li>
              <li>
                <strong>Dynamic Type / larger text support</strong> — text scales up to 200%+
                without loss of content or functionality.
              </li>
              <li>
                <strong>Dark mode support</strong> — a full dark appearance is available to
                reduce eye strain and improve readability in low-light settings.
              </li>
              <li>
                <strong>Color-independent status indicators</strong> — we use icons alongside
                color so that status information is never conveyed by color alone.
              </li>
              <li>
                <strong>Reduced motion support</strong> — animations are minimized or removed
                when the user has enabled "Reduce Motion" in their system settings.
              </li>
              <li>
                <strong>Keyboard navigation</strong> — all pages and interactive elements on the
                website are fully navigable with a keyboard.
              </li>
              <li>
                <strong>Sufficient color contrast</strong> — text and interactive elements meet
                WCAG AA contrast ratios.
              </li>
            </ul>
          </section>

          <section>
            <h2>Conformance Goal</h2>
            <p>
              We aim to conform to the Web Content Accessibility Guidelines (WCAG) 2.1 at Level
              AA for our website and follow Apple's Human Interface Guidelines for accessibility
              in our iOS app.
            </p>
          </section>

          <section>
            <h2>Ongoing Efforts</h2>
            <p>
              Accessibility is not a one-time effort. We continuously test with assistive
              technologies, review our designs for inclusive patterns, and address issues as they
              are found. Each release is evaluated for accessibility regressions.
            </p>
          </section>

          <section>
            <h2>Feedback</h2>
            <p>
              If you encounter an accessibility barrier or have suggestions for improvement, we
              want to hear from you. Please email us at{' '}
              <a href="mailto:support@wellvo.net">support@wellvo.net</a> with "Accessibility"
              in the subject line. We take every report seriously and will do our best to
              respond promptly.
            </p>
          </section>
        </div>
      </div>
    </main>
  )
}
