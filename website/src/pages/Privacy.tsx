import './Legal.css'

export default function Privacy() {
  return (
    <main className="legal-page">
      <div className="container">
        <div className="legal-content">
          <h1>Privacy Policy</h1>
          <p className="legal-updated">Last updated: March 17, 2026</p>

          <section>
            <h2>Introduction</h2>
            <p>
              Wellvo ("we," "our," or "us") is committed to protecting your privacy. This Privacy
              Policy explains how we collect, use, disclose, and safeguard your information when
              you use our mobile application and related services (collectively, the "Service").
            </p>
            <p>
              By using the Service, you agree to the collection and use of information in
              accordance with this policy. If you do not agree with our policies and practices,
              do not use the Service.
            </p>
          </section>

          <section>
            <h2>Information We Collect</h2>

            <h3>Information You Provide</h3>
            <ul>
              <li>
                <strong>Account Information:</strong> When you create an account, we collect your
                email address, display name, and optionally your phone number.
              </li>
              <li>
                <strong>Profile Information:</strong> You may optionally provide a profile photo.
              </li>
              <li>
                <strong>Check-In Data:</strong> When a Receiver checks in, we record the time of
                check-in and optional mood selection (happy, neutral, or tired).
              </li>
              <li>
                <strong>Family Group Data:</strong> Information about family groups you create or
                join, including member roles and settings.
              </li>
            </ul>

            <h3>Information Collected Automatically</h3>
            <ul>
              <li>
                <strong>Device Information:</strong> Device type, operating system version, and
                unique device identifiers for push notification delivery.
              </li>
              <li>
                <strong>Usage Data:</strong> App interaction data such as feature usage and
                check-in patterns, collected through privacy-first analytics.
              </li>
            </ul>

            <h3>Information We Do NOT Collect</h3>
            <ul>
              <li>Precise or coarse location data</li>
              <li>Health or fitness data</li>
              <li>Financial information (payments are handled by Apple)</li>
              <li>Browsing or search history</li>
              <li>Contacts list</li>
              <li>Microphone or camera recordings</li>
            </ul>
          </section>

          <section>
            <h2>How We Use Your Information</h2>
            <p>We use the information we collect to:</p>
            <ul>
              <li>Provide, operate, and maintain the Service</li>
              <li>Send daily check-in notifications at your configured times</li>
              <li>Deliver escalation alerts when check-ins are missed</li>
              <li>Display check-in history, streaks, and trends on your dashboard</li>
              <li>Process on-demand check-in requests</li>
              <li>Manage your subscription and family group</li>
              <li>Send important service-related communications</li>
              <li>Improve and optimize the Service</li>
            </ul>
          </section>

          <section>
            <h2>Data Sharing and Disclosure</h2>
            <p>
              We do not sell, rent, or trade your personal information to third parties. We may
              share your information only in the following circumstances:
            </p>
            <ul>
              <li>
                <strong>Within Your Family Group:</strong> Check-in status, mood data, and
                activity are shared with members of your family group based on their role
                (Owner, Receiver, or Viewer).
              </li>
              <li>
                <strong>Service Providers:</strong> We use essential infrastructure providers
                to host and operate the Service. These providers process data only on our behalf.
              </li>
              <li>
                <strong>Legal Requirements:</strong> We may disclose information if required by
                law, regulation, legal process, or governmental request.
              </li>
            </ul>
          </section>

          <section>
            <h2>Data Security</h2>
            <p>
              We implement appropriate technical and organizational measures to protect your
              personal information, including encryption in transit and at rest, secure
              authentication via Apple Sign-In, and regular security reviews.
            </p>
          </section>

          <section>
            <h2>Data Retention</h2>
            <p>
              We retain your check-in data based on your subscription tier: 7 days for Free
              plans, 90 days for Family plans, and unlimited for Family+ plans. Account
              information is retained as long as your account is active. You may request
              deletion of your data at any time.
            </p>
          </section>

          <section>
            <h2>Your Rights</h2>
            <p>Depending on your location, you may have the following rights:</p>
            <ul>
              <li>
                <strong>Access:</strong> Request a copy of the personal data we hold about you.
              </li>
              <li>
                <strong>Correction:</strong> Request correction of inaccurate personal data.
              </li>
              <li>
                <strong>Deletion:</strong> Request deletion of your personal data.
              </li>
              <li>
                <strong>Export:</strong> Request a portable copy of your data.
              </li>
              <li>
                <strong>Opt-Out:</strong> Opt out of certain data processing activities.
              </li>
            </ul>
            <p>
              To exercise any of these rights, contact us at{' '}
              <a href="mailto:privacy@wellvo.net">privacy@wellvo.net</a>.
            </p>
          </section>

          <section>
            <h2>GDPR Compliance (European Users)</h2>
            <p>
              If you are in the European Economic Area, we process your personal data based on
              the following legal bases: your consent, performance of a contract, and our
              legitimate interests in operating and improving the Service. You have the right to
              withdraw consent at any time, lodge a complaint with a supervisory authority, and
              exercise all rights under the GDPR.
            </p>
          </section>

          <section>
            <h2>CCPA Compliance (California Users)</h2>
            <p>
              If you are a California resident, you have the right to know what personal
              information we collect, request deletion of your data, and opt out of the sale of
              your personal information. We do not sell personal information.
            </p>
          </section>

          <section>
            <h2>Children's Privacy</h2>
            <p>
              The Service is designed for users ages 13 and older. We do not knowingly collect
              personal information from children under 13. If we discover that a child under 13
              has provided us with personal information, we will promptly delete it.
            </p>
          </section>

          <section>
            <h2>Third-Party Analytics</h2>
            <p>
              We use privacy-first analytics tools that do not use cookies, do not track users
              across websites, and do not collect personally identifiable information. We do not
              use any third-party advertising or tracking SDKs.
            </p>
          </section>

          <section>
            <h2>Changes to This Policy</h2>
            <p>
              We may update this Privacy Policy from time to time. We will notify you of any
              material changes by posting the new policy on this page and updating the "Last
              updated" date. Continued use of the Service after changes constitutes acceptance
              of the updated policy.
            </p>
          </section>

          <section>
            <h2>Contact Us</h2>
            <p>
              If you have questions about this Privacy Policy or our data practices, please
              contact us at:
            </p>
            <p>
              <strong>Email:</strong>{' '}
              <a href="mailto:privacy@wellvo.net">privacy@wellvo.net</a>
              <br />
              <strong>Website:</strong>{' '}
              <a href="https://wellvo.net/support">wellvo.net/support</a>
            </p>
          </section>
        </div>
      </div>
    </main>
  )
}
