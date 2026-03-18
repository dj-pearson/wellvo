import { Link } from 'react-router-dom'
import { Mail, MessageCircle, FileText, HelpCircle } from 'lucide-react'
import './Support.css'

const faqs = [
  {
    q: 'How do I set up Wellvo for my family?',
    a: 'Download Wellvo from the App Store, create an account, and set up your family group. Then invite your loved ones via SMS or QR code — they\'ll receive a link to join automatically.',
  },
  {
    q: 'What happens if my loved one misses a check-in?',
    a: 'Wellvo uses an escalating alert system. First, your loved one gets a gentle reminder. If they still don\'t respond, you\'ll be notified. You can customize all timing windows from 15 to 120 minutes.',
  },
  {
    q: 'Can my parent respond without opening the app?',
    a: 'Yes! Receivers can respond directly from the push notification — no need to unlock their phone or open the app. Just tap the notification action.',
  },
  {
    q: 'How do I cancel my subscription?',
    a: 'Subscriptions are managed through your Apple ID. Go to Settings > [Your Name] > Subscriptions on your iPhone to manage or cancel your Wellvo subscription.',
  },
  {
    q: 'Is Wellvo available on Android?',
    a: 'Currently, Wellvo is available for iPhone only. We\'re evaluating Android support based on demand.',
  },
  {
    q: 'How do I add more family members?',
    a: 'From your Owner dashboard, tap "Add Member" and choose to invite via SMS link or QR code. If you need more members than your plan allows, you can purchase add-on slots.',
  },
  {
    q: 'What are Critical Alerts?',
    a: 'Available on the Family+ plan, Critical Alerts can bypass Do Not Disturb mode on your iPhone. This ensures you never miss an alert when a loved one hasn\'t checked in.',
  },
  {
    q: 'How do I delete my account and data?',
    a: 'Go to Settings in the app and select "Delete Account." This will permanently remove your account and all associated data. You can also email privacy@wellvo.net to request deletion.',
  },
]

export default function Support() {
  return (
    <>
      <section className="support-hero">
        <div className="container">
          <h1>How can we help?</h1>
          <p>Find answers to common questions or reach out to our support team.</p>
        </div>
      </section>

      <section className="section support-contact">
        <div className="container">
          <div className="contact-grid">
            <div className="contact-card">
              <Mail size={28} />
              <h3>Email Support</h3>
              <p>Get help from our team. We typically respond within 24 hours.</p>
              <a href="mailto:support@wellvo.net" className="btn btn-secondary">
                support@wellvo.net
              </a>
            </div>
            <div className="contact-card">
              <MessageCircle size={28} />
              <h3>In-App Support</h3>
              <p>Family+ subscribers get priority support directly within the app.</p>
              <Link to="/pricing" className="btn btn-secondary">
                View Plans
              </Link>
            </div>
            <div className="contact-card">
              <FileText size={28} />
              <h3>Legal & Privacy</h3>
              <p>Questions about your data, privacy rights, or our policies.</p>
              <a href="mailto:privacy@wellvo.net" className="btn btn-secondary">
                privacy@wellvo.net
              </a>
            </div>
          </div>
        </div>
      </section>

      <section className="section support-faq">
        <div className="container">
          <div className="section-header">
            <HelpCircle size={32} className="faq-header-icon" />
            <h2>Frequently Asked Questions</h2>
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

      <section className="section support-cta">
        <div className="container">
          <div className="support-cta-card">
            <h3>Still need help?</h3>
            <p>
              Our support team is here for you. Reach out anytime and we'll get back
              to you as soon as possible.
            </p>
            <a href="mailto:support@wellvo.net" className="btn btn-primary">
              Contact Support
            </a>
          </div>
        </div>
      </section>
    </>
  )
}
