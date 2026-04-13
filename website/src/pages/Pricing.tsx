import { useEffect } from 'react'
import { Link } from 'react-router-dom'
import { Check, ArrowRight } from 'lucide-react'
import { trackEvent } from '../utils/analytics'
import SEO, { APP_STORE_URL } from '../components/SEO'
import './Pricing.css'

const plans = [
  {
    name: 'Caregiver',
    price: '$3.99',
    period: '/month',
    yearlyPrice: '$29.99/year',
    yearlySaving: 'Save 37%',
    description: 'Built for the adult child watching over one aging parent',
    receivers: 1,
    viewers: 3,
    features: [
      'Daily + on-demand check-ins',
      'Full escalation chain',
      'Mood tracking',
      'Pattern alerts',
      '90-day check-in history',
      'SMS fallback alerts',
    ],
    cta: 'Start 7-Day Free Trial',
    highlight: true,
  },
  {
    name: 'Family',
    price: '$6.99',
    period: '/month',
    yearlyPrice: '$49.99/year',
    yearlySaving: 'Save 40%',
    description: 'For monitoring both parents, or a parent and a teen',
    receivers: 3,
    viewers: 5,
    features: [
      'Everything in Caregiver, plus:',
      'Clinician-ready PDF export',
      '1-year check-in history',
      'Kid mode for teen Receivers',
      'Custom check-in schedules',
    ],
    cta: 'Start 7-Day Free Trial',
    highlight: false,
  },
  {
    name: 'Family+',
    price: '$9.99',
    period: '/month',
    yearlyPrice: '$79.99/year',
    yearlySaving: 'Save 33%',
    description: 'For larger extended families who need the most peace of mind',
    receivers: 6,
    viewers: 10,
    features: [
      'Everything in Family, plus:',
      'Critical Alerts (bypass DND)',
      'Unlimited check-in history',
      'Priority support',
    ],
    cta: 'Start 7-Day Free Trial',
    highlight: false,
  },
]

const addons = [
  {
    name: 'Additional Receiver',
    price: '$2.49',
    period: '/month each',
    description: 'Add more family members to check in on (Family or Family+ plans)',
  },
  {
    name: 'Additional Viewer',
    price: '$0.99',
    period: '/month each',
    description: 'Add more family members who can view the dashboard (Family or Family+ plans)',
  },
]

export default function Pricing() {
  useEffect(() => {
    trackEvent('pricing_page_view')
  }, [])

  const pricingFaqs = [
    { q: 'Who pays for the subscription?', a: 'Only the Owner (the person managing the family group) pays. Receivers and Viewers never see billing or need to pay anything.' },
    { q: 'Can I try before I buy?', a: 'Yes. Every plan includes a 7-day free trial on monthly, or a 14-day free trial on yearly. You won\'t be charged until the trial ends, and you can cancel anytime from your Apple ID or Google Play settings.' },
    { q: 'Which plan is right for a parent with dementia?', a: 'The Caregiver plan. It\'s sized for exactly that situation — one Receiver (the parent) and up to 3 Viewers (you and your siblings who all want peace of mind). Pattern alerts are included, which help you spot changes in daily routine that can signal dementia progression.' },
    { q: 'How does Daily OK compare to medical alert devices?', a: 'Medical alerts like Life Alert or Medical Guardian cost $30–50/month and are designed for emergency response. Daily OK is for daily connection and early warning — a fraction of the price, no hardware, and built around one simple tap instead of a call center.' },
    { q: 'What happens if I cancel?', a: 'Your plan stays active until the end of your billing period. After that, check-ins stop being sent. Your data is retained per our data retention policy and you can export or delete it anytime.' },
    { q: 'Can I switch plans?', a: 'Yes, you can upgrade or downgrade anytime. Changes take effect at your next billing date. Upgrades are prorated.' },
    { q: 'What are Critical Alerts?', a: 'On the Family+ plan, missed check-in alerts can bypass Do Not Disturb mode on your iPhone — so you\'ll never miss a 3 AM escalation because your phone was on silent.' },
    { q: 'Is my data safe?', a: 'Absolutely. We\'re GDPR and CCPA compliant with full data export and deletion controls. No location tracking, no microphone access, no third-party tracking SDKs.' },
  ]

  const faqJsonLd = {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    mainEntity: pricingFaqs.map((faq) => ({
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
        title="Pricing — Caregiver, Family & Family+ Plans"
        description="Daily OK pricing starts at $3.99/mo for the Caregiver plan — built for families watching over one parent with dementia. Family ($6.99/mo) and Family+ ($9.99/mo with Critical Alerts) for larger households. Every plan includes a free trial."
        path="/pricing"
        keywords="dailyok pricing, dementia caregiver app cost, family check-in app price, elderly parent monitoring app subscription, caregiver app free trial"
        jsonLd={faqJsonLd}
      />

      <section className="pricing-hero">
        <div className="container">
          <h1>Simple, Transparent Pricing</h1>
          <p>Start with a free trial. Cancel anytime.</p>
        </div>
      </section>

      <section className="section pricing-plans">
        <div className="container">
          <div className="plans-grid">
            {plans.map((plan) => (
              <div
                key={plan.name}
                className={`plan-card ${plan.highlight ? 'plan-highlight' : ''}`}
              >
                {plan.highlight && <div className="plan-badge">Most Popular</div>}
                <div className="plan-header">
                  <h3>{plan.name}</h3>
                  <div className="plan-price">
                    <span className="price-amount">{plan.price}</span>
                    <span className="price-period">{plan.period}</span>
                  </div>
                  {plan.yearlyPrice && (
                    <div className="plan-yearly">
                      <span>{plan.yearlyPrice}</span>
                      <span className="yearly-badge">{plan.yearlySaving}</span>
                    </div>
                  )}
                  <p className="plan-desc">{plan.description}</p>
                </div>

                <div className="plan-limits">
                  <div className="limit">
                    <strong>{plan.receivers}</strong> Receiver{plan.receivers !== 1 ? 's' : ''}
                  </div>
                  <div className="limit">
                    <strong>{plan.viewers}</strong> Viewer{plan.viewers !== 1 ? 's' : ''}
                  </div>
                </div>

                <ul className="plan-features">
                  {plan.features.map((feature, i) => (
                    <li key={i}>
                      <Check size={16} />
                      {feature}
                    </li>
                  ))}
                </ul>

                <a
                  href={APP_STORE_URL}
                  className={`btn ${plan.highlight ? 'btn-primary' : 'btn-secondary'} plan-cta`}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {plan.cta}
                  <ArrowRight size={16} />
                </a>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="section addons-section">
        <div className="container">
          <div className="section-header">
            <h2>Add-Ons</h2>
            <p>Need more capacity? Add extra members to your Family or Family+ plan.</p>
          </div>

          <div className="addons-grid">
            {addons.map((addon) => (
              <div key={addon.name} className="addon-card">
                <div>
                  <h4>{addon.name}</h4>
                  <p>{addon.description}</p>
                </div>
                <div className="addon-price">
                  <span className="price-amount">{addon.price}</span>
                  <span className="price-period">{addon.period}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="section pricing-faq">
        <div className="container">
          <div className="section-header">
            <h2>Frequently Asked Questions</h2>
          </div>

          <div className="faq-grid">
            {pricingFaqs.map((faq) => (
              <div key={faq.q} className="faq-item">
                <h4>{faq.q}</h4>
                <p>
                  {faq.a}
                  {faq.q === 'Is my data safe?' && (
                    <>
                      {' '}
                      <Link to="/privacy">Read our Privacy Policy</Link>.
                    </>
                  )}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>
    </>
  )
}
