import { Link } from 'react-router-dom'
import { trackEvent } from '../utils/analytics'
import SEO, { APP_STORE_URL } from '../components/SEO'
import {
  Heart,
  Shield,
  Bell,
  CheckCircle,
  ArrowRight,
  Users,
  TrendingUp,
  Smartphone,
} from 'lucide-react'
import './ElderlyCare.css'

const faqs = [
  {
    q: 'Is Daily OK easy enough for someone with dementia to use?',
    a: 'Yes. Receivers see one large "I\'m OK" button — that\'s the entire interface. They can even respond directly from the push notification without opening the app. No menus, no settings, no confusion. It\'s designed for users who may struggle with complex technology.',
  },
  {
    q: 'What happens if my parent doesn\'t respond to the check-in?',
    a: 'Daily OK uses an escalating alert system. First, your parent gets a gentle reminder. If they still don\'t respond within your configured window (15–120 minutes), you\'re notified. On the Family+ plan, alerts can even bypass Do Not Disturb mode.',
  },
  {
    q: 'Does Daily OK track my parent\'s location?',
    a: 'No. Daily OK never accesses location data, cameras, or microphones. It\'s a simple daily wellness check — not a surveillance tool. We believe in preserving your parent\'s dignity and independence.',
  },
  {
    q: 'Can multiple family members monitor the same parent?',
    a: 'Yes. The Owner manages the family group, and Viewers can see the dashboard too. This is perfect when siblings share caregiving duties — everyone stays informed without duplicating effort.',
  },
  {
    q: 'Can I share check-in reports with a doctor or care provider?',
    a: 'Yes. The Family+ plan includes exportable PDF reports with check-in history, mood trends, and consistency data — exactly the kind of information healthcare providers find useful during appointments.',
  },
  {
    q: 'How is this different from calling my parent every day?',
    a: 'Daily OK is less intrusive and more consistent. Your parent taps one button instead of having a conversation they may not always want. You get a reliable daily signal that doesn\'t depend on either of you being available at the same time. And if they miss it, you know immediately.',
  },
]

export default function ElderlyCare() {
  const faqJsonLd = {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    mainEntity: faqs.map((faq) => ({
      '@type': 'Question',
      name: faq.q,
      acceptedAnswer: {
        '@type': 'Answer',
        text: faq.a,
      },
    })),
  }

  return (
    <>
      <SEO
        title="Daily Check-In App for Elderly Parents & Dementia Caregivers"
        description="Daily OK helps adult children check on aging parents living alone — especially those with dementia or Alzheimer's. One tap daily check-in with escalating alerts. No location tracking. Free on iPhone."
        path="/elderly-care"
        keywords="elderly parent check-in app, dementia caregiver app, alzheimers check-in app, aging parent safety, senior daily check-in, check on elderly parents app, dementia daily wellness check, aging in place app, elderly living alone safety, caregiver peace of mind app, senior wellness monitoring, daily check-in for seniors"
        jsonLd={faqJsonLd}
      />

      {/* Hero */}
      <section className="ec-hero">
        <div className="container ec-hero-inner">
          <div className="hero-badge">For Families of Aging Parents</div>
          <h1 className="ec-hero-title">
            A simple daily check-in for{' '}
            <span className="hero-highlight">elderly parents living alone</span>
          </h1>
          <p className="ec-hero-subtitle">
            If your parent has dementia, Alzheimer's, or is simply aging independently,
            you know the worry that comes with distance. Daily OK gives you a reliable daily
            signal that they're OK — without invasive monitoring, complicated technology,
            or daily phone calls they may not always want.
          </p>
          <div className="hero-actions">
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

      {/* The Problem */}
      <section className="section ec-problem">
        <div className="container">
          <div className="section-header">
            <h2>The daily worry of long-distance caregiving</h2>
            <p>
              Over 53 million Americans are caregivers. If you're one of them, you know
              the anxiety of wondering: "Is Mom OK today?"
            </p>
          </div>

          <div className="ec-problem-grid">
            <div className="ec-problem-card">
              <h4>Daily phone calls feel like a chore</h4>
              <p>
                For both of you. Your parent may not always want to talk, and you can't
                always call at the right time. A check-in shouldn't require a 20-minute conversation.
              </p>
            </div>
            <div className="ec-problem-card">
              <h4>GPS trackers feel like surveillance</h4>
              <p>
                Your parent is an adult who deserves dignity. Location tracking, cameras,
                and wearable monitors can feel controlling — and many seniors refuse them.
              </p>
            </div>
            <div className="ec-problem-card">
              <h4>Dementia makes technology harder</h4>
              <p>
                Complex apps with menus, settings, and multiple screens are impossible for
                someone experiencing cognitive decline. They need something incredibly simple.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Solution */}
      <section className="section ec-solution">
        <div className="container">
          <div className="section-header">
            <h2>Daily OK: One button. Total peace of mind.</h2>
            <p>Designed to be simple enough for anyone — including those with cognitive challenges</p>
          </div>

          <div className="ec-solution-grid">
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><Bell size={28} /></div>
              <h3>Gentle daily notification</h3>
              <p>
                At the time you choose, your parent gets a simple push notification
                asking them to check in. No confusing messages — just a friendly prompt.
              </p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><Smartphone size={28} /></div>
              <h3>One giant "I'm OK" button</h3>
              <p>
                That's the entire app for your parent. One oversized button with large text.
                They can even respond directly from the notification without opening the app.
              </p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><Shield size={28} /></div>
              <h3>Escalating alerts if no response</h3>
              <p>
                If your parent misses their check-in, Daily OK sends them a reminder first.
                If they still don't respond, you get alerted — and so do other family members
                you've designated as Viewers.
              </p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><TrendingUp size={28} /></div>
              <h3>Patterns that tell a story</h3>
              <p>
                Track check-in consistency, mood trends, and response times over weeks and
                months. Changes in patterns can be early indicators worth discussing with
                a healthcare provider.
              </p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><Users size={28} /></div>
              <h3>Coordinate with siblings</h3>
              <p>
                Add siblings and other family members as Viewers so everyone stays informed.
                No more "Did you hear from Mom today?" group texts.
              </p>
            </div>
            <div className="ec-solution-card">
              <div className="ec-solution-icon"><Heart size={28} /></div>
              <h3>Dignity-first design</h3>
              <p>
                No location tracking. No cameras. No microphone access. No wearables.
                Daily OK preserves your parent's independence while giving you peace of mind.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Dementia-specific */}
      <section className="section ec-dementia">
        <div className="container">
          <div className="section-header">
            <h2>Built with dementia and Alzheimer's families in mind</h2>
          </div>

          <div className="ec-dementia-grid">
            <div className="ec-dementia-item">
              <CheckCircle size={20} />
              <div>
                <h4>VoiceOver & Dynamic Type support</h4>
                <p>Full accessibility for vision-impaired seniors. Text scales up to 200%+.</p>
              </div>
            </div>
            <div className="ec-dementia-item">
              <CheckCircle size={20} />
              <div>
                <h4>No menus or navigation</h4>
                <p>The receiver interface is a single screen with a single button. Nothing to get lost in.</p>
              </div>
            </div>
            <div className="ec-dementia-item">
              <CheckCircle size={20} />
              <div>
                <h4>Notification-based response</h4>
                <p>Your parent can respond without even opening the app — reducing cognitive load.</p>
              </div>
            </div>
            <div className="ec-dementia-item">
              <CheckCircle size={20} />
              <div>
                <h4>Consistent daily routine</h4>
                <p>Same time, same prompt, same button. Routine is important for people with dementia.</p>
              </div>
            </div>
            <div className="ec-dementia-item">
              <CheckCircle size={20} />
              <div>
                <h4>Critical Alerts bypass DND</h4>
                <p>On Family+, missed check-in alerts can bypass Do Not Disturb — because some alerts can't wait.</p>
              </div>
            </div>
            <div className="ec-dementia-item">
              <CheckCircle size={20} />
              <div>
                <h4>PDF reports for care providers</h4>
                <p>Export check-in history and trends to share during doctor visits or care team meetings.</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="section ec-faq">
        <div className="container">
          <div className="section-header">
            <h2>Frequently asked questions about elderly parent check-ins</h2>
          </div>

          <div className="faq-list">
            {faqs.map((faq, i) => (
              <details key={i} className="faq-item-detail">
                <summary>{faq.q}</summary>
                <p>{faq.a}</p>
              </details>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="section cta-section">
        <div className="container">
          <div className="cta-card">
            <h2>Give yourself peace of mind — starting today</h2>
            <p>
              The Caregiver plan ($3.99/mo) is built for exactly this: one parent,
              full escalation, pattern alerts for dementia progression. Try it free for 7 days.
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
            <p className="cta-footnote">
              Worried right now and can't reach them? Start with{' '}
              <Link to="/welfare-check-on-elderly-parent/">
                how to request a welfare check
              </Link>
              . Otherwise, read how the{' '}
              <Link to="/check-in-app-for-elderly/">check-in app for elderly parents</Link>{' '}
              works, or the case for{' '}
              <Link to="/daily-check-in-app-for-seniors/">
                daily check-ins for seniors aging in place
              </Link>
              .
            </p>
          </div>
        </div>
      </section>
    </>
  )
}
