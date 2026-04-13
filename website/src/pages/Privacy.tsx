import SEO from '../components/SEO'
import './Legal.css'

export default function Privacy() {
  return (
    <main className="legal-page">
      <SEO
        title="Privacy Policy"
        description="Daily OK privacy policy. Transparent data practices, optional location, GDPR, CCPA/CPRA, COPPA, and state privacy law compliance."
        path="/privacy"
        keywords="dailyok privacy, family app privacy policy, GDPR, CCPA, CPRA, COPPA"
      />
      <div className="container">
        <div className="legal-content">
          <h1>Privacy Policy</h1>
          <p className="legal-updated">Last updated: April 13, 2026</p>

          <section>
            <h2>Introduction</h2>
            <p>
              Daily OK is provided by Pearson Media LLC ("Daily OK," "we," "our," or "us"). This
              Privacy Policy explains how we collect, use, disclose, retain, and safeguard
              personal information when you use our mobile applications, website, and related
              services (collectively, the "Service").
            </p>
            <p>
              By using the Service you agree to the practices described here. If you do not
              agree, please do not use the Service. This Policy is incorporated into our{' '}
              <a href="/terms">Terms of Use</a>.
            </p>
          </section>

          <section>
            <h2>Summary of Key Practices</h2>
            <ul>
              <li>We do not sell or "share" personal information for cross-context behavioral advertising.</li>
              <li>We do not use third-party advertising or tracking SDKs.</li>
              <li>Location is optional and only collected with your in-app permission.</li>
              <li>You can export or delete your data at any time from app settings.</li>
              <li>We honor opt-out and deletion requests for residents of all U.S. states with applicable privacy laws.</li>
            </ul>
          </section>

          <section>
            <h2>Information We Collect</h2>

            <h3>Information You Provide</h3>
            <ul>
              <li>
                <strong>Account Information:</strong> Email address, display name, and optionally
                a phone number for SMS escalation alerts.
              </li>
              <li>
                <strong>Profile Information:</strong> Optional profile photo and time zone.
              </li>
              <li>
                <strong>Family Group Data:</strong> Information about family groups you create or
                join, member roles (Owner, Receiver, Viewer), and check-in schedules you configure.
              </li>
              <li>
                <strong>Check-In Data:</strong> Timestamps when a Receiver checks in and an
                optional mood selection (happy, neutral, or tired).
              </li>
              <li>
                <strong>Optional Location:</strong> If a Receiver enables the location feature,
                we collect approximate coordinates (typically accurate to ~100 meters) attached
                to a check-in or significant change in location, so the family group knows the
                Receiver is in their usual area. Location collection is off by default,
                requires the operating system permission prompt, and can be revoked at any time.
              </li>
              <li>
                <strong>Communications:</strong> Messages you send to support, including the
                contents of those messages and any attachments.
              </li>
            </ul>

            <h3>Information Collected Automatically</h3>
            <ul>
              <li>
                <strong>Device &amp; Push Tokens:</strong> Device type, operating system version,
                app version, locale, and the Apple Push Notification service (APNs) or Firebase
                Cloud Messaging (FCM) token used to deliver notifications.
              </li>
              <li>
                <strong>Diagnostic &amp; Usage Data:</strong> Aggregate, non-identifying signals
                such as feature usage counts, crash reports, and performance traces. We use a
                privacy-first analytics provider (Cloudflare Web Analytics) that does not set
                cookies or identify individuals.
              </li>
              <li>
                <strong>Log Data:</strong> Server logs (IP address, request path, status, and
                user agent) used for security, abuse prevention, and debugging. Log entries are
                retained for up to 30 days.
              </li>
            </ul>

            <h3>Information We Do Not Collect</h3>
            <ul>
              <li>Health, fitness, biometric, or genetic data</li>
              <li>Microphone, camera, or photo library content</li>
              <li>Browsing or search history outside the Service</li>
              <li>Contacts list, calendar, or email body content</li>
              <li>Payment card numbers (handled by Apple App Store and Google Play; we never see your card details)</li>
              <li>Precise advertising identifiers (we do not show ads)</li>
            </ul>
          </section>

          <section>
            <h2>How We Use Your Information</h2>
            <p>We process personal information for the following purposes:</p>
            <ul>
              <li>To provide, operate, and maintain the Service</li>
              <li>To send daily check-in notifications and on-demand check-in requests</li>
              <li>To deliver escalation alerts (push, SMS, or in-app) when a check-in is missed</li>
              <li>To display history, streaks, and trends to authorized members of your family group</li>
              <li>To process and manage your subscription</li>
              <li>To authenticate users and protect against fraud, abuse, and security threats</li>
              <li>To respond to support requests, legal requests, and to comply with our legal obligations</li>
              <li>To improve features, fix bugs, and develop new functionality</li>
            </ul>
          </section>

          <section>
            <h2>Legal Bases for Processing (EEA, UK, Switzerland)</h2>
            <p>If you are located in the EEA, the United Kingdom, or Switzerland, we rely on the following legal bases:</p>
            <ul>
              <li><strong>Performance of a contract</strong> — to provide the Service you signed up for.</li>
              <li><strong>Consent</strong> — for optional location, marketing email, and similar opt-in features. You may withdraw consent at any time.</li>
              <li><strong>Legitimate interests</strong> — to secure the Service, prevent abuse, and improve product quality, balanced against your rights.</li>
              <li><strong>Legal obligation</strong> — to comply with applicable law, court orders, or regulatory requests.</li>
            </ul>
          </section>

          <section>
            <h2>Sharing and Disclosure</h2>
            <p>
              We do not sell personal information, and we do not "share" it for cross-context
              behavioral advertising as those terms are defined under the California Consumer
              Privacy Act, as amended by the CPRA. We disclose information only as follows:
            </p>
            <ul>
              <li>
                <strong>Within Your Family Group:</strong> Check-in status, mood, optional
                location, and activity history are visible to other members of your family
                group based on their assigned role. The Owner controls roles and can remove
                members.
              </li>
              <li>
                <strong>Service Providers (Sub-processors):</strong> We use vetted vendors to
                host infrastructure, deliver notifications, and process payments. A current list
                of sub-processors is below.
              </li>
              <li>
                <strong>Legal &amp; Safety:</strong> When required by law, valid legal process,
                or to protect the rights, property, or safety of users, the public, or Daily OK.
              </li>
              <li>
                <strong>Business Transfers:</strong> In connection with a merger, acquisition,
                financing, or sale of assets, with notice and continued protection of your data.
              </li>
            </ul>

            <h3>Sub-processors</h3>
            <ul>
              <li><strong>Supabase (PostgreSQL hosting and authentication)</strong> — primary application database, encrypted at rest.</li>
              <li><strong>Contabo / Coolify (VPS hosting)</strong> — hosts our edge functions in the European Union.</li>
              <li><strong>Cloudflare</strong> — content delivery, DDoS protection, and privacy-first web analytics.</li>
              <li><strong>Apple Push Notification service (APNs)</strong> — delivery of iOS push notifications.</li>
              <li><strong>Google Firebase Cloud Messaging (FCM)</strong> — delivery of Android push notifications.</li>
              <li><strong>Twilio (SMS)</strong> — escalation text messages where SMS fallback is enabled.</li>
              <li><strong>Apple App Store and Google Play</strong> — payment processing for subscriptions.</li>
            </ul>
          </section>

          <section>
            <h2>International Data Transfers</h2>
            <p>
              Daily OK is operated from infrastructure located in the European Union and the
              United States. Where personal data is transferred across borders, we rely on
              appropriate safeguards such as the European Commission's Standard Contractual
              Clauses (SCCs), the UK International Data Transfer Addendum, and equivalent
              mechanisms. A copy of the safeguards used for a specific transfer is available on
              request to <a href="mailto:privacy@dailyok.net">privacy@dailyok.net</a>.
            </p>
          </section>

          <section>
            <h2>Data Retention</h2>
            <p>We retain personal information only as long as necessary for the purposes described in this Policy:</p>
            <ul>
              <li><strong>Account information:</strong> for the life of your account, plus up to 30 days after deletion to complete removal from backups.</li>
              <li><strong>Check-in history:</strong> 90 days for Caregiver plan, 1 year for Family plan, unlimited for Family+ plan, or until deletion is requested — whichever comes first.</li>
              <li><strong>Optional location data:</strong> attached to the corresponding check-in record and deleted on the same schedule; never retained as a separate location history.</li>
              <li><strong>Server logs:</strong> up to 30 days.</li>
              <li><strong>Support communications:</strong> up to 24 months.</li>
              <li><strong>Tax and billing records:</strong> retained for 7 years to comply with U.S. Internal Revenue Service requirements.</li>
            </ul>
          </section>

          <section>
            <h2>Security</h2>
            <p>
              We implement administrative, technical, and physical safeguards designed to
              protect personal information. These include TLS 1.2+ encryption in transit,
              encryption at rest for the application database, role-based access control with
              least-privilege defaults, multi-factor authentication for staff, secrets
              management, dependency vulnerability scanning, and PostgreSQL row-level security
              for tenant isolation. No method of transmission or storage is 100% secure, and
              you are responsible for keeping your account credentials confidential.
            </p>
            <p>
              If we discover a security incident affecting your personal information, we will
              notify you and applicable regulators as required by law (typically within 72
              hours for jurisdictions with such obligations).
            </p>
          </section>

          <section>
            <h2>Your Privacy Rights</h2>
            <p>Subject to applicable law, you may have the following rights regarding your personal information:</p>
            <ul>
              <li><strong>Access / Know:</strong> request a copy of the information we hold about you.</li>
              <li><strong>Correction / Rectification:</strong> ask us to correct inaccurate information.</li>
              <li><strong>Deletion / Erasure:</strong> ask us to delete your information.</li>
              <li><strong>Portability:</strong> receive your information in a portable, machine-readable format (CSV or JSON).</li>
              <li><strong>Opt-Out of Sale/Sharing:</strong> we do not sell or share personal information; this right is honored by default.</li>
              <li><strong>Limit Use of Sensitive Personal Information:</strong> we do not use sensitive personal information for purposes that would require an opt-out.</li>
              <li><strong>Withdraw Consent:</strong> for processing based on consent (e.g., optional location, marketing email).</li>
              <li><strong>Non-Discrimination:</strong> we will not discriminate against you for exercising any of these rights.</li>
              <li><strong>Appeal:</strong> if we deny your request, you may appeal by replying to our response email; we will respond within 45 days.</li>
            </ul>
            <p>
              You can exercise most of these rights directly from app settings (Export Data,
              Delete Account). You may also contact us at{' '}
              <a href="mailto:privacy@dailyok.net">privacy@dailyok.net</a>. We will verify your
              identity by matching the request to the email address on your account before
              fulfilling it. Authorized agents may submit requests on your behalf with proof of
              authorization.
            </p>
          </section>

          <section>
            <h2>U.S. State Privacy Disclosures</h2>
            <p>
              In addition to the rights above, residents of the following states have specific
              rights under their state's privacy law: California (CCPA/CPRA), Colorado (CPA),
              Connecticut (CTDPA), Virginia (VCDPA), Utah (UCPA), Texas (TDPSA), Oregon
              (OCPA), Montana (MCDPA), Iowa, Tennessee, Indiana, Florida, New Jersey, Delaware,
              New Hampshire, Minnesota, Maryland, Rhode Island, and Kentucky. We honor verified
              consumer requests in line with the law of the consumer's state of residence.
            </p>

            <h3>California (CCPA/CPRA)</h3>
            <p>
              In the preceding 12 months we collected the categories of personal information
              described in "Information We Collect" above. We collected this information for
              the purposes described in "How We Use Your Information," and we disclosed the
              following categories to sub-processors for operational purposes: identifiers,
              account information, device and connection information, and check-in content
              including optional location. <strong>We did not sell or share personal
              information.</strong>
            </p>
            <p>
              California residents may submit requests via{' '}
              <a href="mailto:privacy@dailyok.net">privacy@dailyok.net</a>. You may also direct
              an authorized agent to submit requests on your behalf.
            </p>

            <h3>Colorado, Connecticut, and similar states</h3>
            <p>
              We honor opt-out preference signals (such as the Global Privacy Control) where
              required. Sensitive data (precise location, where collected) is processed only
              with affirmative consent.
            </p>
          </section>

          <section>
            <h2>Children's Privacy</h2>
            <p>
              The Service is intended for users who are at least 13 years old. We do not
              knowingly collect personal information from children under 13. If you are a
              parent or guardian and believe a child under 13 has provided us with personal
              information, please contact{' '}
              <a href="mailto:privacy@dailyok.net">privacy@dailyok.net</a> and we will
              promptly delete the information and the associated account.
            </p>
            <p>
              For users who are minors (13 to the local age of majority), the Owner of the
              family group is responsible for obtaining parental or legal-guardian consent
              before adding the minor as a Receiver or Viewer. Owners must be at least 18.
            </p>
          </section>

          <section>
            <h2>Cookies and Similar Technologies</h2>
            <p>
              The Daily OK website does not use advertising cookies or third-party tracking
              cookies. We use a small number of strictly necessary technologies to operate the
              site (for example, session storage for navigation state) and a privacy-first
              analytics provider that does not set cookies. See our{' '}
              <a href="/cookies">Cookie Notice</a> for details.
            </p>
          </section>

          <section>
            <h2>Do Not Track</h2>
            <p>
              Our website does not respond to browser "Do Not Track" signals because no
              consistent industry standard exists. We do, however, honor recognized opt-out
              preference signals such as Global Privacy Control where required by law.
            </p>
          </section>

          <section>
            <h2>Third-Party Services and Links</h2>
            <p>
              The Service may include links to third-party websites or services (such as the
              App Store, Google Play, or support documentation). Their privacy practices are
              governed by their own policies, and we are not responsible for them.
            </p>
          </section>

          <section>
            <h2>Changes to This Policy</h2>
            <p>
              We may update this Privacy Policy from time to time. If we make material
              changes, we will provide reasonable advance notice (typically 30 days) by
              email, in-app notice, or a banner on our website. The "Last updated" date at
              the top of this page indicates when the Policy was most recently revised.
            </p>
          </section>

          <section>
            <h2>Contact Us</h2>
            <p>
              For questions about this Policy or to exercise your privacy rights, please contact:
            </p>
            <p>
              <strong>Pearson Media LLC — Daily OK Privacy</strong>
              <br />
              Email: <a href="mailto:privacy@dailyok.net">privacy@dailyok.net</a>
              <br />
              Mailing address: Pearson Media LLC, 1234 Example Street, Salt Lake City, UT
              84101, USA{' '}
              <em>(operations address; update as required when finalized)</em>
              <br />
              Website: <a href="https://dailyok.net/support">dailyok.net/support</a>
            </p>
            <p>
              <strong>EU/UK Representative:</strong> Daily OK does not currently maintain a
              physical establishment in the EU or UK. EEA, UK, and Swiss residents may contact
              us at the email address above for privacy matters and may also lodge a
              complaint with their local supervisory authority.
            </p>
          </section>
        </div>
      </div>
    </main>
  )
}
