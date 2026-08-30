import { Link } from 'react-router-dom'
import { trackEvent } from '../utils/analytics'
import SEO, { APP_STORE_URL } from '../components/SEO'
import { buildBreadcrumbJsonLd } from '../lib/breadcrumb'
import { Heart, Bell, Shield, Users, TrendingUp, Smartphone, ArrowRight, CheckCircle } from 'lucide-react'
import './ElderlyCare.css'
import './Landing.css'

const faqs = [
  {
    q: 'What is a peace-of-mind app for elderly parents?',
    a: 'It is an app built less for your parent and more for you — the adult child carrying the worry. Your parent taps "I\'m OK" once a day; you get a quiet confirmation, and an automatic alert if it\'s missing. The product it really delivers is the mental space to stop wondering all day whether your parent is alright.',
  },
  {
    q: 'I already call my mom every day. Why do I need this?',
    a: 'Because a call you have to remember to make, at a time that works for both of you, that tells you nothing if she doesn\'t pick up, is not peace of mind — it is a daily task with a built-in anxiety spike. Daily OK removes the remembering and makes a missed signal actionable instead of terrifying. Keep calling for connection; let the app carry the safety worry.',
  },
  {
    q: 'Will using this make me feel like I\'m being overbearing?',
    a: 'Most adult children report the opposite. Because there\'s no tracking and the parent controls the daily tap, it doesn\'t feel like surveillance to either side. It often reduces friction: fewer "I was just checking on you" calls that parents find patronizing, because the check-in already happened.',
  },
  {
    q: 'What about the guilt of living far away?',
    a: 'Distance guilt usually comes from a feeling of helplessness — being too far to know if something is wrong. Daily OK doesn\'t close the miles, but it does close the information gap: you know every day, and you know fast if you don\'t. For a lot of long-distance children, that is the difference between low-grade dread and being able to be present in their own life.',
  },
  {
    q: 'What happens at 3am if something is wrong?',
    a: 'You configure the check-in window. If a check-in is missed and the window passes, you\'re alerted — and on the Family+ plan that alert can bypass Do Not Disturb so it isn\'t silenced overnight. Siblings added as Viewers get notified too, so it isn\'t all on one person at 3am.',
  },
  {
    q: 'How much does peace of mind cost here?',
    a: 'The Caregiver plan is $3.99/month — one parent, up to three family Viewers, full escalation and pattern alerts. Family ($6.99) and Family+ ($9.99, Critical Alerts) cover bigger families. No hardware, and a 7-day free trial so you can feel the difference before paying.',
  },
]

export default function PeaceOfMindAppForElderlyParents() {
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
      { name: 'Peace-of-Mind App for Elderly Parents', path: '/peace-of-mind-app-for-elderly-parents' },
    ]),
  ]

  return (
    <>
      <SEO
        title="Peace-of-Mind App for Elderly Parents — Stop Wondering All Day"
        description="Daily OK is the peace-of-mind app for adult children of elderly parents. One daily 'I'm OK' tap, automatic alerts if it's missed — so you can stop carrying the worry. No tracking. From $3.99/mo."
        path="/peace-of-mind-app-for-elderly-parents"
        keywords="peace of mind app for elderly parents, app for adult children of aging parents, worry about elderly parent app, long distance caregiver app, app to stop worrying about parents, aging parent reassurance app"
        jsonLd={jsonLd}
      />

      <section className="ec-hero">
        <div className="container ec-hero-inner">
          <nav className="lp-breadcrumb" aria-label="Breadcrumb">
            <Link to="/">Home</Link> &nbsp;/&nbsp; Peace-of-Mind App for Elderly Parents
          </nav>
          <div className="hero-badge">Peace-of-Mind App for Elderly Parents</div>
          <h1 className="ec-hero-title">
            The <span className="hero-highlight">peace-of-mind app</span> for the adult child who can't stop worrying
          </h1>
          <div className="lp-tldr">
            <strong>In short</strong>
            This one's for you, not just your parent. They tap "I'm OK" once a day;
            you get a quiet yes — and an automatic alert if it's missing. The worry
            stops being a background process you run all day.
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
          <h2>The worry is a tax you pay every day</h2>
          <p>
            If you have an aging parent who lives alone, you know the specific
            shape of this. It's the thought that interrupts a meeting. It's the
            reason you check your phone during dinner. It's lying awake at 2am
            doing math about how long it would take to drive there. It's the
            apology you give your own kids for being distracted. Nobody bills you
            for it, but it's a tax — paid in attention, sleep, and the quiet guilt
            that you can't be in two places at once.
          </p>
          <p>
            A peace-of-mind app for elderly parents isn't really a feature list.
            It's a way to stop paying that tax. The mechanics are simple on
            purpose; what they buy back is your ability to be present in your own
            life without abandoning your parent in theirs.
          </p>

          <h2>How it gives the worry somewhere to go</h2>
          <p>
            Your parent is the <strong>Receiver</strong> — one daily notification,
            one "I'm OK" button, answerable without even opening the app. You're
            the <strong>Owner</strong> who sets it up once. Siblings can be{' '}
            <strong>Viewers</strong>, so the load is shared and no single person is
            the designated worrier. Each day you either see a green check and
            genuinely move on, or — if the check-in is missed and your window
            passes — Daily OK escalates: a reminder to your parent first, then an
            alert to you and your Viewers. On Family+, that alert can break through
            Do Not Disturb so an overnight miss doesn't sit silent until morning.
          </p>
          <p>
            The psychological shift is the whole point. Today, silence from your
            parent means <em>you</em> have to notice the silence, interpret it, and
            decide whether to panic. With Daily OK, silence triggers the system, not
            your nervous system. You're allowed to not be thinking about it, because
            something else is.
          </p>

          <div className="lp-phone" role="img" aria-label="Mock-up of the Daily OK check-in screen: a time, a warm prompt, and one large 'I'm OK' button">
            <div className="lp-phone-time">Today, 9:00 AM</div>
            <div className="lp-phone-prompt">Good morning! One tap and your family can relax.</div>
            <div className="lp-phone-btn">I'm OK</div>
          </div>
          <p className="lp-phone-caption">
            Your parent's whole experience. Yours is a green check — and silence handled for you.
          </p>

          <h2>Calling vs. an app that carries it for you</h2>
          <table className="lp-compare-table">
            <thead>
              <tr>
                <th></th>
                <th>The daily call</th>
                <th>Daily OK</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Who has to remember</td>
                <td>You, every single day</td>
                <td>The app prompts your parent automatically</td>
              </tr>
              <tr>
                <td>If there's no answer</td>
                <td>You spiral or drive over</td>
                <td>Auto-escalation; you're alerted with a plan</td>
              </tr>
              <tr>
                <td>Emotional load</td>
                <td>Anxiety spike built into the routine</td>
                <td>Default state is "handled"</td>
              </tr>
              <tr>
                <td>Shared with siblings</td>
                <td>Group texts and double-checking</td>
                <td>One status everyone sees</td>
              </tr>
            </tbody>
          </table>
          <p>
            This isn't an argument to stop calling your mom. Call her — for her
            voice, not for proof of life. Let the call be about love and the app be
            about safety. Conflating the two is what makes the daily call so heavy.
          </p>

          <h2>What changes for you</h2>
          <div className="ec-solution-grid">
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><Heart size={28} /></div>
              <h3>Reclaimed attention</h3>
              <p>Stop running a background worry process during work and family time.</p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><Bell size={28} /></div>
              <h3>Silence is handled</h3>
              <p>A missed check-in becomes the app's job, not your 2am math.</p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><Users size={28} /></div>
              <h3>Shared with siblings</h3>
              <p>No single designated worrier; everyone sees the same status.</p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><Shield size={28} /></div>
              <h3>Critical Alerts</h3>
              <p>Family+ alerts can bypass Do Not Disturb so overnight isn't missed.</p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><TrendingUp size={28} /></div>
              <h3>Early signals</h3>
              <p>Pattern changes surface before they become an emergency call.</p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><Smartphone size={28} /></div>
              <h3>Nothing for them to learn</h3>
              <p>No hardware, no account, no menus on your parent's side.</p>
            </div>
          </div>

          <h2>Why it doesn't feel overbearing</h2>
          <div className="ec-dementia-grid">
            <div className="ec-dementia-item">
              <CheckCircle size={20} />
              <div>
                <h4>No tracking</h4>
                <p>No location, camera, or microphone. It's reassurance, not surveillance.</p>
              </div>
            </div>
            <div className="ec-dementia-item">
              <CheckCircle size={20} />
              <div>
                <h4>Your parent controls it</h4>
                <p>They send the signal. It affirms independence rather than questioning it.</p>
              </div>
            </div>
            <div className="ec-dementia-item">
              <CheckCircle size={20} />
              <div>
                <h4>Fewer "just checking" calls</h4>
                <p>The check-in already happened, so contact can be about connection.</p>
              </div>
            </div>
            <div className="ec-dementia-item">
              <CheckCircle size={20} />
              <div>
                <h4>Quiet by design</h4>
                <p>One prompt a day. It runs in the background of both your lives.</p>
              </div>
            </div>
          </div>

          <h2>What "peace of mind" actually requires</h2>
          <p>
            Peace of mind is not the absence of anything ever going wrong — you
            can't buy that, and any product that implies it is lying to you. Real
            peace of mind is narrower and more honest: confidence that <em>if</em>{' '}
            something goes wrong, you'll find out fast enough to do something about
            it, and certainty that the not-knowing isn't quietly eroding the rest
            of your life in the meantime. Those are two distinct things, and Daily
            OK is built to deliver both — the fast-finding-out through automatic
            escalation, and the relief from the background dread through a default
            state of "handled."
          </p>
          <p>
            It deliberately does not promise to prevent emergencies, detect falls,
            or replace a phone call your parent actually wants. Naming those limits
            is the point: a tool that's honest about what it does is one you can
            actually trust to do it. The worry doesn't disappear because you've
            decided to stop caring — it eases because the specific, recurring,
            information-shaped part of it now has somewhere to go that isn't your
            own head at 2am.
          </p>

          <h2>What the first week usually feels like</h2>
          <p>
            Most adult children describe the same arc. Day one, you watch for the
            check-in like a hawk and feel slightly silly about how relieved the
            green check makes you. By the end of the first week, the relief has
            quietly become the baseline — you notice you went a whole afternoon
            without the intrusive thought, and you only realized it later. That
            shift, from actively monitoring to trusting the system to interrupt you
            only when it matters, is the entire product. It's also why we keep the
            free trial at a full seven days: this is something you have to feel,
            not read about, to believe.
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
            <Link to="/daily-check-in-app-for-seniors/">Daily check-in app for seniors</Link>
            <Link to="/compare/daily-ok-vs-life360/">Daily OK vs Life360</Link>
            <Link to="/compare/daily-ok-vs-life-alert/">Daily OK vs Life Alert</Link>
            <Link to="/blog/">Caregiving guides on the blog</Link>
          </div>
        </div>
      </section>

      <section className="section cta-section">
        <div className="container">
          <div className="cta-card">
            <h2>Stop paying the worry tax</h2>
            <p>
              The Caregiver plan ($3.99/mo) is built for one parent and the family
              who loves them. Free for 7 days — feel the difference first.
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
