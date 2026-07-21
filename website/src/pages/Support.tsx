import { useEffect } from 'react'
import { Link } from 'react-router-dom'
import { Mail, MessageCircle, FileText, HelpCircle } from 'lucide-react'
import { trackEvent } from '../utils/analytics'
import SEO from '../components/SEO'
import './Support.css'

const faqs = [
  {
    q: 'How do I set up Daily OK for my family?',
    a: 'Download Daily OK from the App Store, create an account, and set up your family group. Then invite your loved ones by sending them a text — the app opens your Messages app with a prewritten invite you send from your own phone. When they download the app and sign in with that number, they\'re connected automatically.',
  },
  {
    q: 'What happens if my loved one misses a check-in?',
    a: 'Daily OK uses an escalating alert system. First, your loved one gets a gentle reminder. If they still don\'t respond, you\'ll be notified. You can customize all timing windows from 15 to 120 minutes.',
  },
  {
    q: 'Can my parent respond without opening the app?',
    a: 'Yes! Receivers can respond directly from the push notification — no need to unlock their phone or open the app. Just tap the notification action.',
  },
  {
    q: 'How do I cancel my subscription?',
    a: 'Subscriptions are managed through your Apple ID. Go to Settings > [Your Name] > Subscriptions on your iPhone to manage or cancel your Daily OK subscription.',
  },
  {
    q: 'Is Daily OK available on Android?',
    a: 'Currently, Daily OK is available for iPhone only. We\'re evaluating Android support based on demand.',
  },
  {
    q: 'How do I add more family members?',
    a: 'From your Owner dashboard, tap "Invite Family Member" and enter their name and phone number. The app opens your Messages app with a ready-to-send invite text that goes from your own phone. If you need more members than your plan allows, you can purchase add-on slots.',
  },
  {
    q: 'What are Critical Alerts?',
    a: 'Available on the Family+ plan, Critical Alerts can bypass Do Not Disturb mode on your iPhone. This ensures you never miss an alert when a loved one hasn\'t checked in.',
  },
  {
    q: 'How do I delete my account and data?',
    a: 'Go to Settings in the app and select "Delete Account." This will permanently remove your account and all associated data. You can also email privacy@dailyok.net to request deletion.',
  },
]

export default function Support() {
  useEffect(() => {
    trackEvent('support_page_view')
  }, [])

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
        title="Support & FAQ"
        description="Get help with Daily OK, the daily check-in app for families and caregivers. Find answers about setting up check-ins for elderly parents, children, and loved ones."
        path="/support"
        keywords="dailyok support, daily check-in app help, elderly parent check-in setup, caregiver app FAQ, family safety app support"
        jsonLd={faqJsonLd}
      />

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
              <a href="mailto:support@dailyok.net" className="btn btn-secondary">
                support@dailyok.net
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
              <a href="mailto:privacy@dailyok.net" className="btn btn-secondary">
                privacy@dailyok.net
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
            <a href="mailto:support@dailyok.net" className="btn btn-primary">
              Contact Support
            </a>
          </div>
        </div>
      </section>
    </>
  )
}
