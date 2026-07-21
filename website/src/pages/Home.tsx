import { Link } from 'react-router-dom'
import { trackEvent } from '../utils/analytics'
import SEO, { APP_STORE_URL } from '../components/SEO'
import {
  Heart,
  Shield,
  Bell,
  Users,
  CheckCircle,
  Clock,
  Smartphone,
  TrendingUp,
  ArrowRight,
  MapPin,
  Camera,
  Mic,
} from 'lucide-react'
import './Home.css'

export default function Home() {
  return (
    <>
      <SEO
        title="Daily OK — Senior Check-In App for Aging Parents | Daily &quot;I'm OK&quot; & Care Alerts"
        description="Daily OK is the senior check-in app: set up a once-a-day &quot;I'm OK&quot; for an aging parent and get escalating alerts the moment they miss it. No pendant, no GPS tracking, no cameras. Works for teens and any loved one you worry about, too. From $3.99/mo with a free trial."
        path="/"
        keywords="senior check-in app, check-in app for elderly, daily check-in app for seniors, check-in app for elderly parents, elderly safety app, aging parent check-in, wellness check app, welfare check elderly parent, medical alert alternative, aging in place app, dementia caregiver app, caregiver app for elderly, check on elderly parents, teen check-in app"
      />

      {/* Hero */}
      <section className="hero">
        <div className="container hero-inner">
          <div className="hero-badge">Senior Check-In App for Aging Parents</div>
          <h1 className="hero-title">
            Know your aging parent is OK —{' '}
            <span className="hero-highlight">every single day</span>
          </h1>
          <p className="hero-subtitle">
            Daily OK gives you a reliable daily signal that your aging parent is OK — one
            notification, one tap, no pendant or GPS tracking. The same gentle daily check-in
            works for a teen or anyone else you worry about, too.
          </p>
          <div className="hero-actions">
            <a
              href={APP_STORE_URL}
              className="btn btn-primary btn-lg"
              target="_blank"
              rel="noopener noreferrer"
              onClick={() => trackEvent('download_cta_click')}
            >
              Download for iPhone
              <ArrowRight size={18} />
            </a>
            <Link to="/pricing" className="btn btn-secondary btn-lg">
              View Pricing
            </Link>
          </div>
          <p className="hero-note">7-day free trial on every plan. Cancel anytime.</p>
        </div>
      </section>

      {/* Social proof */}
      <section className="social-proof">
        <div className="container">
          <div className="proof-items">
            <div className="proof-item">
              <strong>53M+</strong>
              <span>American caregivers</span>
            </div>
            <div className="proof-divider" />
            <div className="proof-item">
              <strong>Ages 13–95</strong>
              <span>Senior-friendly by design</span>
            </div>
            <div className="proof-divider" />
            <div className="proof-item">
              <strong>1 Tap</strong>
              <span>That's all it takes</span>
            </div>
          </div>
        </div>
      </section>

      {/* How it works */}
      <section className="section how-it-works" id="how-it-works">
        <div className="container">
          <div className="section-header">
            <h2>How Daily OK Works</h2>
            <p>Simple for everyone involved — set up in under 2 minutes</p>
          </div>

          <div className="steps-grid">
            <div className="step-card">
              <div className="step-number">1</div>
              <div className="step-icon">
                <Users size={28} />
              </div>
              <h3>Set Up Your Family</h3>
              <p>
                Create your account, add family members, and set each person's
                daily check-in time based on their routine.
              </p>
            </div>

            <div className="step-card">
              <div className="step-number">2</div>
              <div className="step-icon">
                <Bell size={28} />
              </div>
              <h3>They Get a Notification</h3>
              <p>
                At their scheduled time, your loved one receives a gentle push
                notification asking them to check in.
              </p>
            </div>

            <div className="step-card">
              <div className="step-number">3</div>
              <div className="step-icon">
                <CheckCircle size={28} />
              </div>
              <h3>One Tap: "I'm OK"</h3>
              <p>
                They tap a single large button — that's it. They can even
                respond directly from the notification without opening the app.
              </p>
            </div>

            <div className="step-card">
              <div className="step-number">4</div>
              <div className="step-icon">
                <Heart size={28} />
              </div>
              <h3>You Get Peace of Mind</h3>
              <p>
                See real-time check-in status on your dashboard. If someone
                misses their check-in, escalating alerts make sure nothing slips through.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="section features" id="features">
        <div className="container">
          <div className="section-header">
            <h2>Everything You Need</h2>
            <p>Powerful features wrapped in the simplest possible experience</p>
          </div>

          <div className="features-grid">
            <div className="feature-card">
              <div className="feature-icon">
                <Shield size={24} />
              </div>
              <h3>Escalating Alerts</h3>
              <p>
                Configurable escalation chain — gentle reminders first, then
                owner alerts, then viewer alerts. Timing is fully customizable (15–120 min).
              </p>
            </div>

            <div className="feature-card">
              <div className="feature-icon">
                <Smartphone size={24} />
              </div>
              <h3>On-Demand Check-Ins</h3>
              <p>
                Worried right now? Send an instant "checking on you" ping
                anytime with a single tap on your dashboard.
              </p>
            </div>

            <div className="feature-card">
              <div className="feature-icon">
                <TrendingUp size={24} />
              </div>
              <h3>History & Insights</h3>
              <p>
                Calendar heatmaps, streak tracking, mood trends, and exportable
                PDF reports — perfect for sharing with healthcare providers.
              </p>
            </div>

            <div className="feature-card">
              <div className="feature-icon">
                <Clock size={24} />
              </div>
              <h3>Custom Schedules</h3>
              <p>
                Each family member gets their own check-in time based on their
                timezone and daily routine. Fully personalized.
              </p>
            </div>

            <div className="feature-card">
              <div className="feature-icon">
                <Users size={24} />
              </div>
              <h3>Family Management</h3>
              <p>
                Invite family members with a quick text from your phone. Assign
                roles — Receivers check in, Viewers monitor dashboards.
              </p>
            </div>

            <div className="feature-card">
              <div className="feature-icon">
                <Bell size={24} />
              </div>
              <h3>Critical Alerts</h3>
              <p>
                Family+ plan alerts can bypass Do Not Disturb mode — because
                some notifications are too important to miss.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Two sides */}
      <section className="section two-sides">
        <div className="container">
          <div className="sides-grid">
            <div className="side-card owner-side">
              <div className="side-label">For You (the Owner)</div>
              <h3>Your Dashboard, Your Peace of Mind</h3>
              <ul>
                <li><CheckCircle size={18} /> Real-time status cards for each family member</li>
                <li><CheckCircle size={18} /> "Check on [Name]" quick-action buttons</li>
                <li><CheckCircle size={18} /> Today's timeline of all check-ins</li>
                <li><CheckCircle size={18} /> Weekly summary with consistency stats</li>
                <li><CheckCircle size={18} /> Pattern alerts when behavior shifts</li>
                <li><CheckCircle size={18} /> Mood trend tracking over time</li>
              </ul>
            </div>

            <div className="side-card receiver-side">
              <div className="side-label">For Your Loved One (the Receiver)</div>
              <h3>One Button. That's the Entire App.</h3>
              <ul>
                <li><CheckCircle size={18} /> Giant "I'm OK" button — impossible to miss</li>
                <li><CheckCircle size={18} /> Respond from notification — no app needed</li>
                <li><CheckCircle size={18} /> Optional mood indicator (happy / neutral / tired)</li>
                <li><CheckCircle size={18} /> No settings, menus, or confusion</li>
                <li><CheckCircle size={18} /> Full VoiceOver and Dynamic Type support</li>
                <li><CheckCircle size={18} /> Works beautifully for ages 13 to 95</li>
              </ul>
            </div>
          </div>
        </div>
      </section>

      {/* Not surveillance */}
      <section className="section not-surveillance">
        <div className="container">
          <div className="section-header">
            <h2>Care, Not Surveillance</h2>
            <p>Daily OK respects the dignity and independence of your loved ones</p>
          </div>

          <div className="no-tracking-grid">
            <div className="no-track-item">
              <div className="no-icon"><MapPin size={24} /></div>
              <h4>Location Is Optional</h4>
              <p>
                Receivers can choose to attach a location pin to their check-in. Location is
                only collected with your permission, never sold, and can be turned off at any
                time. <a href="/privacy">Learn more</a>.
              </p>
            </div>
            <div className="no-track-item">
              <div className="no-icon"><Camera size={24} /></div>
              <h4>No Cameras or Sensors</h4>
              <p>No video, no audio monitoring, no wearables required.</p>
            </div>
            <div className="no-track-item">
              <div className="no-icon"><Mic size={24} /></div>
              <h4>No Microphone Access</h4>
              <p>We never request or use the microphone.</p>
            </div>
            <div className="no-track-item">
              <div className="no-icon"><Shield size={24} /></div>
              <h4>GDPR & CCPA/CPRA Compliant</h4>
              <p>Full data export, deletion, and retention controls — yours to manage.</p>
            </div>
          </div>
        </div>
      </section>

      {/* Perfect for */}
      <section className="section perfect-for">
        <div className="container">
          <div className="section-header">
            <h2>Perfect For</h2>
            <p>Designed for the people who worry most — and the ones they worry about</p>
          </div>

          <div className="use-cases-grid">
            <div className="use-case">
              <div className="use-case-emoji" role="img" aria-label="Elderly woman">👵</div>
              <h4>Aging Parents & Dementia Care</h4>
              <p>
                Adult children checking on parents living alone — especially those with
                early-stage dementia or Alzheimer's. A simple, dignified daily wellness check
                without invasive monitoring.
              </p>
              <Link to="/elderly-care" className="use-case-link">Learn more</Link>
            </div>
            <div className="use-case">
              <div className="use-case-emoji" role="img" aria-label="Children playing">👦</div>
              <h4>Kids & Teens</h4>
              <p>
                Parents of children playing outside, walking home from school, or staying home
                alone. A quick daily check-in so you know they're safe — without hovering.
              </p>
              <Link to="/child-safety" className="use-case-link">Learn more</Link>
            </div>
            <div className="use-case">
              <div className="use-case-emoji" role="img" aria-label="Globe">🌍</div>
              <h4>Long-Distance Families</h4>
              <p>
                Stay connected with family across states or countries. A daily "I'm OK" signal
                that bridges the distance and eases the worry.
              </p>
            </div>
            <div className="use-case">
              <div className="use-case-emoji" role="img" aria-label="Stethoscope">🩺</div>
              <h4>Family & Professional Caregivers</h4>
              <p>
                Whether you're a professional caregiver or a family member coordinating care,
                Daily OK provides a reliable daily wellness signal with history and PDF reports
                you can share with healthcare providers.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="section cta-section">
        <div className="container">
          <div className="cta-card">
            <h2>Start checking in today</h2>
            <p>Try any plan free for 7 days. Caregiver plan from $3.99/month.</p>
            <div className="cta-actions">
              <a
                href={APP_STORE_URL}
                className="btn btn-primary btn-lg"
                target="_blank"
                rel="noopener noreferrer"
                onClick={() => trackEvent('download_cta_click')}
              >
                Download for iPhone
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
