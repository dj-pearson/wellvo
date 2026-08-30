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
  MapPin,
  Camera,
  Mic,
} from 'lucide-react'
import './ChildSafety.css'

const faqs = [
  {
    q: 'What age is Daily OK appropriate for?',
    a: 'Daily OK is designed for users ages 13 and up (as Receivers). The one-tap interface is simple enough for any teenager, and many younger teens find it easier than remembering to text their parents.',
  },
  {
    q: 'Does Daily OK track my child\'s location?',
    a: 'No. Daily OK never accesses location data. It\'s a simple "I\'m OK" check-in — not a tracking app. This approach respects your child\'s growing independence while keeping you informed.',
  },
  {
    q: 'What if my child forgets to check in?',
    a: 'Daily OK sends a gentle reminder first. If they still don\'t respond within your configured time window (15–120 minutes), you get an alert. On the Family+ plan, alerts can bypass Do Not Disturb on your phone.',
  },
  {
    q: 'Can my child respond without opening the app?',
    a: 'Yes! They can tap the "I\'m OK" action directly from the push notification. No need to unlock the phone or open the app — perfect for kids who are busy playing.',
  },
  {
    q: 'Can I check on multiple children?',
    a: 'Yes. The Family plan supports 3 receivers and the Family+ plan supports 6. You can also purchase additional receiver slots. Each child gets their own check-in schedule.',
  },
  {
    q: 'How is this different from just texting my kid?',
    a: 'Texts get lost in group chats, ignored, or forgotten. Daily OK is a dedicated, structured check-in with escalating alerts if there\'s no response. It\'s consistent, reliable, and takes the guesswork out of "Did they see my message?"',
  },
]

export default function ChildSafety() {
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
        title="Daily Check-In App for Kids & Teen Safety"
        description="Daily OK helps parents stay connected with children playing outside, walking home from school, or home alone. Simple one-tap daily check-in with alerts. No GPS tracking. Free on iPhone."
        path="/child-safety"
        keywords="child safety check-in app, kids check-in app, teen safety app, latchkey kid app, child wellness check app, kids playing outside safety, after school check-in app, parent child check-in, child safety app no tracking, teen check-in app for parents, kid home alone safety app"
        jsonLd={faqJsonLd}
      />

      {/* Hero */}
      <section className="cs-hero">
        <div className="container cs-hero-inner">
          <div className="hero-badge">For Parents of Kids & Teens</div>
          <h1 className="cs-hero-title">
            Know your kids are safe —{' '}
            <span className="hero-highlight">without hovering</span>
          </h1>
          <p className="cs-hero-subtitle">
            Whether they're playing outside, walking home from school, or staying home
            alone — Daily OK lets you check in with your children every day. One notification.
            One tap. No GPS tracking, no surveillance. Just a simple "I'm OK."
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

      {/* Use Cases */}
      <section className="section cs-scenarios">
        <div className="container">
          <div className="section-header">
            <h2>Perfect for everyday parenting moments</h2>
            <p>The times when you just need to know they're alright</p>
          </div>

          <div className="cs-scenarios-grid">
            <div className="cs-scenario-card">
              <div className="cs-scenario-emoji" role="img" aria-label="Bicycle">🚲</div>
              <h4>Playing outside</h4>
              <p>
                Kids riding bikes, playing at the park, or hanging out with friends in the
                neighborhood. Set a check-in for when they should be heading home.
              </p>
            </div>
            <div className="cs-scenario-card">
              <div className="cs-scenario-emoji" role="img" aria-label="School">🏫</div>
              <h4>Walking home from school</h4>
              <p>
                A daily check-in timed to when they should arrive home. If they don't
                respond, you'll know right away — not an hour later.
              </p>
            </div>
            <div className="cs-scenario-card">
              <div className="cs-scenario-emoji" role="img" aria-label="House">🏠</div>
              <h4>Home alone after school</h4>
              <p>
                Latchkey kids who let themselves in. A quick check-in confirms they got
                home safely so you can focus at work.
              </p>
            </div>
            <div className="cs-scenario-card">
              <div className="cs-scenario-emoji" role="img" aria-label="Tent">⛺</div>
              <h4>Summer activities & camps</h4>
              <p>
                When kids are at day camps, summer programs, or spending time at a
                friend's house. Stay connected without being overbearing.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Why not just text */}
      <section className="section cs-why-not-text">
        <div className="container">
          <div className="section-header">
            <h2>Better than texting "Are you OK?"</h2>
          </div>

          <div className="cs-compare-grid">
            <div className="cs-compare-card cs-compare-old">
              <h4>Texting</h4>
              <ul>
                <li>Gets buried in group chats</li>
                <li>No way to know if they saw it</li>
                <li>Relies on you remembering to ask</li>
                <li>No escalation if ignored</li>
                <li>No history or patterns</li>
              </ul>
            </div>
            <div className="cs-compare-card cs-compare-new">
              <h4>Daily OK</h4>
              <ul>
                <li><CheckCircle size={16} /> Dedicated check-in notification</li>
                <li><CheckCircle size={16} /> One-tap response from notification</li>
                <li><CheckCircle size={16} /> Automatic daily scheduling</li>
                <li><CheckCircle size={16} /> Escalating alerts if no response</li>
                <li><CheckCircle size={16} /> Calendar history and mood tracking</li>
              </ul>
            </div>
          </div>
        </div>
      </section>

      {/* Privacy for kids */}
      <section className="section cs-privacy">
        <div className="container">
          <div className="section-header">
            <h2>Safety without surveillance</h2>
            <p>
              We believe kids deserve privacy too. Daily OK checks in —
              it doesn't track, watch, or listen.
            </p>
          </div>

          <div className="cs-privacy-grid">
            <div className="cs-privacy-item">
              <div className="no-icon"><MapPin size={24} /></div>
              <h4>No GPS tracking</h4>
              <p>We never access your child's location</p>
            </div>
            <div className="cs-privacy-item">
              <div className="no-icon"><Camera size={24} /></div>
              <h4>No camera access</h4>
              <p>No photos, no video, no screen monitoring</p>
            </div>
            <div className="cs-privacy-item">
              <div className="no-icon"><Mic size={24} /></div>
              <h4>No microphone</h4>
              <p>We never listen in — ever</p>
            </div>
            <div className="cs-privacy-item">
              <div className="no-icon"><Shield size={24} /></div>
              <h4>No social features</h4>
              <p>No messaging, no friends list, no social pressure</p>
            </div>
          </div>
        </div>
      </section>

      {/* How it works for kids */}
      <section className="section cs-how">
        <div className="container">
          <div className="section-header">
            <h2>How it works for your family</h2>
          </div>

          <div className="cs-steps-grid">
            <div className="cs-step">
              <div className="cs-step-num">1</div>
              <div className="cs-step-icon"><Users size={28} /></div>
              <h3>Set up your family</h3>
              <p>Create your account and invite your children with a quick text from your own phone. Set each child's check-in time based on their schedule.</p>
            </div>
            <div className="cs-step">
              <div className="cs-step-num">2</div>
              <div className="cs-step-icon"><Bell size={28} /></div>
              <h3>They get a notification</h3>
              <p>At their scheduled time, your child receives a friendly push notification. They tap "I'm OK" — that's it.</p>
            </div>
            <div className="cs-step">
              <div className="cs-step-num">3</div>
              <div className="cs-step-icon"><Heart size={28} /></div>
              <h3>You get peace of mind</h3>
              <p>See their status on your dashboard. If they miss it, you'll get escalating alerts so nothing slips through.</p>
            </div>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="section cs-faq">
        <div className="container">
          <div className="section-header">
            <h2>Frequently asked questions about child check-ins</h2>
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
            <h2>Start checking in with your kids today</h2>
            <p>
              Free plan includes daily check-ins for 1 child. No credit card required.
            </p>
            <div className="cta-actions">
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
              <Link to="/pricing/" className="btn btn-outline btn-lg">
                Compare Plans
              </Link>
            </div>
            <p className="cta-footnote">
              Looking after a parent as well as a child? The same one-tap check-in is built
              out for that on the{' '}
              <Link to="/peace-of-mind-app-for-elderly-parents/">
                peace-of-mind app for elderly parents
              </Link>{' '}
              page.
            </p>
          </div>
        </div>
      </section>
    </>
  )
}
