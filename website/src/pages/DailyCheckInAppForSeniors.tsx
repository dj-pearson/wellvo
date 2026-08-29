import { Link } from 'react-router-dom'
import { trackEvent } from '../utils/analytics'
import SEO, { APP_STORE_URL } from '../components/SEO'
import { buildBreadcrumbJsonLd } from '../lib/breadcrumb'
import { Home as HomeIcon, Shield, Bell, TrendingUp, Smartphone, Heart, ArrowRight, CheckCircle } from 'lucide-react'
import './ElderlyCare.css'
import './Landing.css'

const faqs = [
  {
    q: 'What is a daily check-in app for seniors?',
    a: 'A daily check-in app for seniors is a phone app that prompts an older adult once a day to confirm they are fine with a single tap, and automatically notifies chosen family members if the check-in is missed. It is designed to support aging in place — staying in your own home safely — rather than moving to a facility for monitoring alone.',
  },
  {
    q: 'How does a check-in app support aging in place?',
    a: 'Many seniors move to assisted living mainly so someone notices if something goes wrong, not because they need daily care. A check-in app provides that "someone notices" layer at home: a missed check-in escalates to family within an hour. It buys independent years by removing the single biggest argument for moving out — the fear of an unnoticed emergency.',
  },
  {
    q: 'Is this a replacement for assisted living or home care?',
    a: 'No, and it should not be presented as one. Daily OK does not provide medical care, fall detection hardware, or in-person help. It is a low-cost early-warning layer for an independent senior who is otherwise doing well at home. If someone needs hands-on daily care, that is a different need.',
  },
  {
    q: 'Will the check-in feel like being monitored?',
    a: 'It is deliberately the opposite of surveillance. There is no location tracking, no camera, no microphone — just a daily yes/no the senior controls by tapping a button. Many older adults prefer it precisely because it preserves autonomy: it proves "I\'m fine on my own" rather than implying they can\'t be.',
  },
  {
    q: 'What if a senior forgets to check in some days?',
    a: 'That is expected, and it is exactly what the escalation system is for. A gentle reminder goes to the senior first. Only if the full window passes does it reach family. Over time the app also shows consistency patterns, which help distinguish "forgot once" from a meaningful change in routine worth a conversation.',
  },
  {
    q: 'How much does it cost compared to monitored care?',
    a: 'Daily OK starts at $3.99/month with no hardware. Monitored medical-alert services typically run $25–$50+/month plus equipment, and assisted living averages thousands per month. For an independent senior, a check-in app is the lowest-cost way to add a safety net without changing how or where they live.',
  },
]

export default function DailyCheckInAppForSeniors() {
  const jsonLd = [
    {
      '@context': 'https://schema.org',
      '@type': 'FAQPage',
      mainEntity: faqs.map((f) => ({
        '@type': 'Question',
        name: f.q,
        acceptedAnswer: { '@type': 'Answer', text: f.a },
      })),
    },
    buildBreadcrumbJsonLd([
      { name: 'Home', path: '/' },
      { name: 'Daily Check-In App for Seniors', path: '/daily-check-in-app-for-seniors' },
    ]),
  ]

  return (
    <>
      <SEO
        title="Daily Check-In App for Seniors — Aging in Place, Safely"
        description="Daily OK is a daily check-in app for seniors who want to stay independent at home. One tap a day proves they're fine; family is alerted if it's missed. No hardware, no tracking. From $3.99/mo."
        path="/daily-check-in-app-for-seniors"
        keywords="daily check in app for seniors, check in app for seniors, senior check in app, aging in place app, senior independence app, app for seniors living alone, daily wellness check for seniors, stay at home senior safety app"
        jsonLd={jsonLd}
      />

      <section className="ec-hero">
        <div className="container ec-hero-inner">
          <nav className="lp-breadcrumb" aria-label="Breadcrumb">
            <Link to="/">Home</Link> &nbsp;/&nbsp; Daily Check-In App for Seniors
          </nav>
          <div className="hero-badge">Daily Check-In App for Seniors</div>
          <h1 className="ec-hero-title">
            A <span className="hero-highlight">daily check-in app for seniors</span> who'd rather stay home than be watched
          </h1>
          <div className="lp-tldr">
            <strong>In short</strong>
            One tap a day proves a senior is doing fine on their own. If it's
            missed, family is alerted within the hour. It's the safety net that
            makes aging in place defensible — without a pendant, a camera, or a move.
          </div>
          <div className="hero-actions" style={{ marginTop: '1.5rem' }}>
            <a
              href={APP_STORE_URL}
              className="btn btn-primary btn-lg"
              target="_blank"
              rel="noopener noreferrer"
              onClick={() => trackEvent('download_cta_click')}
            >
              Download Free for iPhone
              <ArrowRight size={18} />
            </a>
            <Link to="/pricing/" className="btn btn-secondary btn-lg">
              View Plans
            </Link>
          </div>
        </div>
      </section>

      <section className="section">
        <div className="container lp-prose">
          <h2>The real reason seniors leave home early</h2>
          <p>
            Ask families why an independent parent moved to assisted living and the
            honest answer is often not "they needed daily care." It's "we were
            afraid something would happen and no one would know for days." That fear
            — the unnoticed fall, the silent night — is doing an enormous amount of
            work. It pushes capable seniors out of homes they love, years before
            they actually need hands-on help, and it costs families thousands of
            dollars a month to buy what is, at its core, the feeling that someone is
            paying attention.
          </p>
          <p>
            A daily check-in app for seniors targets that exact fear directly and
            cheaply. It doesn't pretend to provide care. It provides the one thing
            the fear is really about: a guarantee that if something is wrong,
            someone finds out fast.
          </p>

          <h2>How Daily OK works for an independent senior</h2>
          <p>
            The senior is the <strong>Receiver</strong>: once a day, at a time they
            help choose, a friendly notification asks them to tap "I'm OK". That's
            the whole interaction — no account, no menus, and they can answer right
            from the notification. A family member is the <strong>Owner</strong> who
            does the setup, and other relatives can be <strong>Viewers</strong> so
            the responsibility is shared, not dumped on one person.
          </p>
          <p>
            If the senior taps in, everyone sees a green check and gets on with
            their day — no phone tag, no "just checking" calls that can feel
            patronizing. If the check-in is missed, Daily OK reminds the senior
            first, then escalates to family only if the window passes. The senior
            stays in control of the signal; the family gets certainty instead of
            worry. On Family+, escalations can bypass Do Not Disturb so an overnight
            miss isn't discovered too late.
          </p>

          <div className="lp-phone" role="img" aria-label="Mock-up of the Daily OK check-in screen for a senior: a time, a short prompt, and one large 'I'm OK' button">
            <div className="lp-phone-time">Today, 10:00 AM</div>
            <div className="lp-phone-prompt">Tap to let your family know all is well today.</div>
            <div className="lp-phone-btn">I'm OK</div>
          </div>
          <p className="lp-phone-caption">
            Independence-first: the senior owns the daily signal. One tap, no tracking.
          </p>

          <h2>Where a check-in app fits</h2>
          <table className="lp-compare-table">
            <thead>
              <tr>
                <th>Option</th>
                <th>Typical monthly cost</th>
                <th>What it actually buys</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Daily check-in app (Daily OK)</td>
                <td>$3.99–$9.99</td>
                <td>Early warning if a healthy, independent senior goes silent</td>
              </tr>
              <tr>
                <td>Monitored medical-alert</td>
                <td>$25–$50+ plus equipment</td>
                <td>Press-button SOS during an emergency (if worn)</td>
              </tr>
              <tr>
                <td>In-home care visits</td>
                <td>Hundreds–thousands</td>
                <td>Hands-on help with daily tasks</td>
              </tr>
              <tr>
                <td>Assisted living</td>
                <td>Thousands</td>
                <td>Care plus the "someone notices" assurance, away from home</td>
              </tr>
            </tbody>
          </table>
          <p>
            Read that table honestly: a check-in app does the least — and for an
            independent senior who is doing well, the least is exactly what's
            needed. It is not a substitute for real care; it is the cheapest way to
            delay needing the more expensive rows for as long as living at home is
            genuinely working.
          </p>

          <h2>Designed for autonomy, not oversight</h2>
          <div className="ec-dementia-grid">
            <div className="ec-dementia-item">
              <CheckCircle size={20} />
              <div>
                <h4>No location, ever</h4>
                <p>The app cannot see where the senior is. It only knows "tapped" or "didn't".</p>
              </div>
            </div>
            <div className="ec-dementia-item">
              <CheckCircle size={20} />
              <div>
                <h4>The senior controls the signal</h4>
                <p>They prove they're fine — it's the opposite of being checked up on.</p>
              </div>
            </div>
            <div className="ec-dementia-item">
              <CheckCircle size={20} />
              <div>
                <h4>No new device to learn</h4>
                <p>Runs on the phone they already use. Nothing to wear or charge.</p>
              </div>
            </div>
            <div className="ec-dementia-item">
              <CheckCircle size={20} />
              <div>
                <h4>Quiet by default</h4>
                <p>One prompt a day. No constant notifications or family hovering.</p>
              </div>
            </div>
          </div>

          <h2>Why families choose it for aging in place</h2>
          <div className="ec-solution-grid">
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><HomeIcon size={28} /></div>
              <h3>Stay home longer</h3>
              <p>Removes the single biggest argument for an early facility move.</p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><Bell size={28} /></div>
              <h3>Fast escalation</h3>
              <p>A missed day reaches family within the hour, not after a weekend.</p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><TrendingUp size={28} /></div>
              <h3>Trend visibility</h3>
              <p>Consistency patterns reveal change early, while options are still open.</p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><Shield size={28} /></div>
              <h3>Critical Alerts</h3>
              <p>Family+ alerts can bypass Do Not Disturb for overnight misses.</p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><Smartphone size={28} /></div>
              <h3>No hardware cost</h3>
              <p>Nothing to buy, install, wear, or replace batteries in.</p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><Heart size={28} /></div>
              <h3>Dignity preserved</h3>
              <p>A safety net that doesn't treat independence as a problem to manage.</p>
            </div>
          </div>

          <h2>When a check-in app is the right fit — and when it isn't</h2>
          <p>
            Being honest about the boundaries is part of taking aging seriously. A
            daily check-in app is the right tool when a senior is genuinely living
            independently: cooking, managing medications, getting around the house,
            and mentally sharp enough to tap a button reliably. In that situation it
            adds an enormous amount of reassurance for a few dollars a month, and it
            often defers a facility move by years. It is the right first step for
            families who are "a little worried" but not yet "actively managing care."
          </p>
          <p>
            It is the wrong tool — or at least not enough on its own — when the
            picture is different. If a senior has a high fall risk and won't move
            for help after a fall, a pendant or fall-detection device addresses that
            specific danger more directly. If memory loss means the daily tap itself
            becomes unreliable, the missed-check-in signal gets noisy and a more
            structured care arrangement is the honest answer. And if someone already
            needs help with daily living tasks, a check-in is a complement to care,
            not a replacement for it. We would rather a family use Daily OK for the
            years it genuinely fits than oversell it for a situation it can't carry.
          </p>

          <h2>Setting it up for a senior who isn't tech-savvy</h2>
          <p>
            The setup burden lives entirely with the family member, by design. As
            the Owner you install the app, pick the daily time (a time the senior is
            reliably awake and has their phone nearby works best — mid-morning is a
            common choice), set the escalation window, and add any siblings as
            Viewers. The senior's phone only needs notifications enabled. From then
            on their entire world is a single daily prompt and one button — no
            updates to manage, no passwords, nothing that breaks if they tap the
            wrong thing, because there is nothing else to tap.
          </p>

          <h2>Frequently asked questions</h2>
          <div className="faq-list">
            {faqs.map((f, i) => (
              <details key={i} className="faq-item-detail">
                <summary>{f.q}</summary>
                <p>{f.a}</p>
              </details>
            ))}
          </div>

          <h2>Keep reading</h2>
          <div className="lp-links">
            <Link to="/pricing/">Pricing &amp; plans</Link>
            <Link to="/elderly-care/">How Daily OK works for elderly care</Link>
            <Link to="/check-in-app-for-elderly/">Check-in app for elderly parents</Link>
            <Link to="/peace-of-mind-app-for-elderly-parents/">Peace-of-mind app for elderly parents</Link>
            <Link to="/compare/daily-ok-vs-life-alert/">Daily OK vs Life Alert</Link>
            <Link to="/compare/daily-ok-vs-snug-safety/">Daily OK vs Snug Safety</Link>
            <Link to="/blog/">Caregiving guides on the blog</Link>
          </div>
        </div>
      </section>

      <section className="section cta-section">
        <div className="container">
          <div className="cta-card">
            <h2>Help a senior stay home, safely</h2>
            <p>
              The Caregiver plan ($3.99/mo) adds the safety net that makes aging in
              place defensible. Free for 7 days, no hardware.
            </p>
            <div className="cta-actions">
              <a
                href={APP_STORE_URL}
                className="btn btn-primary btn-lg"
                target="_blank"
                rel="noopener noreferrer"
                onClick={() => trackEvent('download_cta_click')}
              >
                Start Free Trial
                <ArrowRight size={18} />
              </a>
              <Link to="/pricing/" className="btn btn-outline btn-lg">
                Compare Plans
              </Link>
            </div>
          </div>
        </div>
      </section>
    </>
  )
}
