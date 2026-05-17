import { Link } from 'react-router-dom'
import { trackEvent } from '../utils/analytics'
import SEO, { APP_STORE_URL } from '../components/SEO'
import { buildBreadcrumbJsonLd } from '../lib/breadcrumb'
import { Bell, Smartphone, Shield, TrendingUp, Users, Heart, ArrowRight, CheckCircle } from 'lucide-react'
import './ElderlyCare.css'
import './Landing.css'

const faqs = [
  {
    q: 'What is a check-in app for the elderly?',
    a: 'A check-in app for the elderly is a phone app that asks an older adult to confirm they are OK once a day with a single tap. If they do not respond within a set window, the app automatically alerts family members. Unlike a medical-alert pendant, it is proactive — it checks every day rather than waiting for the person to press a button in an emergency.',
  },
  {
    q: 'Is a check-in app better than calling every day?',
    a: 'They solve different problems. A daily phone call is a conversation that depends on both people being free at the same time, and a missed call tells you nothing definitive. A check-in app gives you a reliable yes/no daily signal in seconds, and — crucially — escalates automatically if the answer is missing. Many families use both: the app for certainty, the call for connection.',
  },
  {
    q: 'Will my elderly parent actually use it?',
    a: 'The entire interface for the older adult is one large "I\'m OK" button, and they can respond straight from the notification without opening the app. There are no menus, accounts, or settings on their side — you set everything up. Adoption is far higher than apps that require the senior to navigate a dashboard.',
  },
  {
    q: 'Does it track location or use the camera?',
    a: 'No. Daily OK never accesses location, camera, or microphone. It is a wellness check, not a surveillance tool. This is deliberate: seniors are far more willing to use something that respects their independence.',
  },
  {
    q: 'What happens when a check-in is missed?',
    a: 'Daily OK escalates in stages. First the older adult gets a gentle reminder. If there is still no response within your configured window (15–120 minutes), you are notified, along with any other family members you added as Viewers. On the Family+ plan, the alert can bypass Do Not Disturb so it is not silenced overnight.',
  },
  {
    q: 'How much does a check-in app for the elderly cost?',
    a: 'Daily OK starts at $3.99/month for the Caregiver plan (one older adult, up to three family Viewers). Family ($6.99/mo) and Family+ ($9.99/mo, with Critical Alerts) cover larger households. There is no hardware to buy and every plan has a 7-day free trial.',
  },
]

export default function CheckInAppForElderly() {
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
      { name: 'Check-In App for Elderly', path: '/check-in-app-for-elderly' },
    ]),
  ]

  return (
    <>
      <SEO
        title="Check-In App for Elderly Parents — One Tap a Day, Auto Alerts"
        description="Daily OK is a check-in app for the elderly: your aging parent taps 'I'm OK' once a day and family is alerted automatically if they don't. No hardware, no location tracking. From $3.99/mo."
        path="/check-in-app-for-elderly"
        keywords="check in app for elderly, check in app for elderly parents, elderly check in app, daily check in for elderly, app to check on elderly parent, senior check in app, wellness check app for seniors, elderly safety app no hardware"
        jsonLd={jsonLd}
      />

      <section className="ec-hero">
        <div className="container ec-hero-inner">
          <nav className="lp-breadcrumb" aria-label="Breadcrumb">
            <Link to="/">Home</Link> &nbsp;/&nbsp; Check-In App for Elderly
          </nav>
          <div className="hero-badge">Check-In App for the Elderly</div>
          <h1 className="ec-hero-title">
            A <span className="hero-highlight">check-in app for elderly parents</span> that asks once a day — and tells you if no one answers
          </h1>
          <div className="lp-tldr">
            <strong>In short</strong>
            Your elderly parent taps one "I'm OK" button each day. If they miss it,
            Daily OK escalates a reminder to them, then alerts you and your family
            automatically. No pendant, no GPS, no daily phone call required.
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
            <Link to="/pricing" className="btn btn-secondary btn-lg">
              View Plans
            </Link>
          </div>
        </div>
      </section>

      <section className="section">
        <div className="container lp-prose">
          <h2>Why families look for a check-in app for the elderly</h2>
          <p>
            More than 53 million Americans are unpaid caregivers, and a large share
            of them are adult children worried about a parent who lives alone. The
            recurring question is simple and exhausting: <em>"Is Mom OK today?"</em>{' '}
            A phone call is the traditional answer, but it is a poor monitoring tool.
            Calls get missed for harmless reasons — a nap, a shower, a dead phone —
            and a missed call gives you anxiety without information. You either
            spiral, or you drive over, or you tell yourself it's probably nothing.
            None of those are good options at 9pm on a work night.
          </p>
          <p>
            A check-in app for the elderly inverts the problem. Instead of you
            chasing confirmation, the confirmation comes to you — and the absence of
            it triggers an alert on its own. That single design change is the whole
            point: silence becomes actionable instead of ambiguous.
          </p>

          <h2>How Daily OK works</h2>
          <p>
            Daily OK has three roles. You are the <strong>Owner</strong> — you set
            the daily check-in time and the escalation window. Your parent is the{' '}
            <strong>Receiver</strong> — their entire experience is one notification
            and one button. Siblings or other relatives can be added as{' '}
            <strong>Viewers</strong> so everyone sees the same status without a
            group text. Each day at the time you chose, your parent gets a friendly
            prompt. They tap "I'm OK". You see a green check. Done.
          </p>
          <p>
            If they don't respond, the escalation ladder runs automatically: a
            gentle reminder to your parent first, then a notification to you and
            your Viewers if the window passes. On Family+, that alert can break
            through Do Not Disturb, because a missed 7am check-in shouldn't wait
            until you happen to glance at your phone at noon. Over time, Daily OK
            also surfaces patterns — later check-ins, more missed days, mood trends —
            that can be early signals worth raising with a doctor.
          </p>

          <div className="lp-phone" role="img" aria-label="Mock-up of the Daily OK check-in screen: a date, a prompt, and one large 'I'm OK' button">
            <div className="lp-phone-time">Today, 9:00 AM</div>
            <div className="lp-phone-prompt">Good morning! Tap below to let your family know you're OK.</div>
            <div className="lp-phone-btn">I'm OK</div>
          </div>
          <p className="lp-phone-caption">
            The entire app, from your parent's side. One button — they can even tap it from the notification.
          </p>

          <h2>Check-in app vs. the alternatives</h2>
          <table className="lp-compare-table">
            <thead>
              <tr>
                <th>Approach</th>
                <th>What it does</th>
                <th>Best when</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Daily check-in app (Daily OK)</td>
                <td>Proactive once-a-day "I'm OK" with automatic escalation</td>
                <td>You want daily reassurance and early warning, no hardware</td>
              </tr>
              <tr>
                <td>Medical-alert pendant</td>
                <td>Reactive SOS the wearer presses during an emergency</td>
                <td>Fall risk is the primary concern and the person will wear it</td>
              </tr>
              <tr>
                <td>GPS / location tracker</td>
                <td>Continuous location of the person</td>
                <td>Wandering risk; accepted by the person being tracked</td>
              </tr>
              <tr>
                <td>Daily phone call</td>
                <td>Human contact, no automation</td>
                <td>Connection matters more than guaranteed monitoring</td>
              </tr>
            </tbody>
          </table>
          <p>
            These are complementary, not mutually exclusive. Many Daily OK families
            keep a pendant for fall risk and use Daily OK for the daily certainty a
            pendant can't give — a pendant only helps if it's worn and pressed. See
            the full breakdowns on our comparison pages below.
          </p>

          <h2>Built so an older adult will actually use it</h2>
          <div className="ec-dementia-grid">
            <div className="ec-dementia-item">
              <CheckCircle size={20} />
              <div>
                <h4>One screen, one button</h4>
                <p>No menus, no login, no settings on the senior's side. You configure everything.</p>
              </div>
            </div>
            <div className="ec-dementia-item">
              <CheckCircle size={20} />
              <div>
                <h4>Respond from the notification</h4>
                <p>They never have to find or open the app to check in.</p>
              </div>
            </div>
            <div className="ec-dementia-item">
              <CheckCircle size={20} />
              <div>
                <h4>Accessibility built in</h4>
                <p>VoiceOver support and Dynamic Type scaling for vision-impaired users.</p>
              </div>
            </div>
            <div className="ec-dementia-item">
              <CheckCircle size={20} />
              <div>
                <h4>Dignity by design</h4>
                <p>No location, camera, or microphone access — ever.</p>
              </div>
            </div>
          </div>

          <h2>What you get as the family</h2>
          <div className="ec-solution-grid">
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><Bell size={28} /></div>
              <h3>Automatic escalation</h3>
              <p>Missed check-ins reach you without you having to remember to look.</p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><Users size={28} /></div>
              <h3>Shared with siblings</h3>
              <p>Everyone sees one status. No more "did you hear from Dad?" threads.</p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><TrendingUp size={28} /></div>
              <h3>Pattern alerts</h3>
              <p>Gradual changes in routine surface before they become a crisis.</p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><Shield size={28} /></div>
              <h3>Critical Alerts</h3>
              <p>On Family+, missed-check-in alerts can bypass Do Not Disturb.</p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><Smartphone size={28} /></div>
              <h3>No hardware</h3>
              <p>Works on the phone your parent already owns — iPhone or Android.</p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><Heart size={28} /></div>
              <h3>Less friction, more peace</h3>
              <p>A daily signal that doesn't depend on either of you being free to talk.</p>
            </div>
          </div>

          <h2>Setting it up takes about five minutes</h2>
          <p>
            One reason families put off solving this is the assumption that any
            "system" means hardware, installation, or teaching an 80-year-old new
            technology. Daily OK is deliberately the opposite. You download the app,
            choose the daily check-in time, set how long the escalation window
            should be, and add siblings as Viewers if you want the responsibility
            shared. Your parent's phone just needs notifications turned on. There is
            nothing to mount, charge, pair, or subscribe to a monitoring center for.
            The whole setup is shorter than the phone call you'd otherwise be making
            to check on them today.
          </p>
          <p>
            From then on it runs itself. There's no dashboard your parent has to
            visit and no maintenance on your side beyond glancing at a green check.
            If circumstances change — a new daily routine, a different time that
            works better, an extra family member who wants visibility — you adjust
            it in seconds without touching your parent's phone at all.
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
            <Link to="/pricing">Pricing &amp; plans</Link>
            <Link to="/elderly-care">How Daily OK works for elderly care</Link>
            <Link to="/daily-check-in-app-for-seniors">Daily check-in app for seniors</Link>
            <Link to="/peace-of-mind-app-for-elderly-parents">Peace-of-mind app for elderly parents</Link>
            <Link to="/compare/daily-ok-vs-life-alert">Daily OK vs Life Alert</Link>
            <Link to="/compare/daily-ok-vs-life360">Daily OK vs Life360</Link>
            <Link to="/blog">Caregiving guides on the blog</Link>
          </div>
        </div>
      </section>

      <section className="section cta-section">
        <div className="container">
          <div className="cta-card">
            <h2>Start checking in today</h2>
            <p>
              The Caregiver plan ($3.99/mo) is built for exactly this — one elderly
              parent, full escalation, pattern alerts. Free for 7 days.
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
              <Link to="/pricing" className="btn btn-outline btn-lg">
                Compare Plans
              </Link>
            </div>
          </div>
        </div>
      </section>
    </>
  )
}
