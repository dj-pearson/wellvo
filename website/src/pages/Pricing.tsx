import { useEffect } from 'react'
import { Link } from 'react-router-dom'
import { Check, ArrowRight } from 'lucide-react'
import { trackEvent } from '../utils/analytics'
import './Pricing.css'

const plans = [
  {
    name: 'Free',
    price: '$0',
    period: '/month',
    description: 'Get started with basic check-ins for one person',
    receivers: 1,
    viewers: 0,
    features: [
      'Daily check-in for 1 person',
      'Push notification alerts',
      '7-day check-in history',
      'Basic escalation alerts',
    ],
    cta: 'Get Started Free',
    highlight: false,
  },
  {
    name: 'Family',
    price: '$4.99',
    period: '/month',
    yearlyPrice: '$39.99/year',
    yearlySaving: 'Save 33%',
    description: 'Perfect for monitoring a couple of family members',
    receivers: 2,
    viewers: 2,
    features: [
      'Everything in Free, plus:',
      'Custom check-in schedules',
      'On-demand check-ins',
      'Full escalation chain',
      'Mood tracking',
      '90-day check-in history',
      'Pattern alerts',
    ],
    cta: 'Start 7-Day Free Trial',
    highlight: true,
  },
  {
    name: 'Family+',
    price: '$7.99',
    period: '/month',
    yearlyPrice: '$59.99/year',
    yearlySaving: 'Save 37%',
    description: 'For larger families who need the most peace of mind',
    receivers: 5,
    viewers: 5,
    features: [
      'Everything in Family, plus:',
      'Critical Alerts (bypass DND)',
      'Exportable PDF reports',
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
    price: '$1.99',
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

  return (
    <>
      <section className="pricing-hero">
        <div className="container">
          <h1>Simple, Transparent Pricing</h1>
          <p>Start free. Upgrade when your family needs grow.</p>
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
                  href="https://apps.apple.com/app/wellvo"
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
            <div className="faq-item">
              <h4>Who pays for the subscription?</h4>
              <p>
                Only the Owner (the person managing the family group) pays. Receivers and Viewers
                never see billing or need to pay anything.
              </p>
            </div>
            <div className="faq-item">
              <h4>Can I try before I buy?</h4>
              <p>
                Yes! The Free plan lets you check in with 1 person forever. Paid plans include
                a 7-day free trial (monthly) or 14-day free trial (yearly).
              </p>
            </div>
            <div className="faq-item">
              <h4>What happens if I cancel?</h4>
              <p>
                Your plan stays active until the end of your billing period. After that, you'll
                be moved to the Free plan. Your data is retained per our data retention policy.
              </p>
            </div>
            <div className="faq-item">
              <h4>Can I switch plans?</h4>
              <p>
                Yes, you can upgrade or downgrade anytime. Changes take effect at your next
                billing date. Upgrades are prorated.
              </p>
            </div>
            <div className="faq-item">
              <h4>What are Critical Alerts?</h4>
              <p>
                On the Family+ plan, missed check-in alerts can bypass Do Not Disturb mode on
                your iPhone — ensuring you never miss an important notification.
              </p>
            </div>
            <div className="faq-item">
              <h4>Is my data safe?</h4>
              <p>
                Absolutely. We're GDPR and CCPA compliant with full data export and deletion
                controls. We use no third-party tracking SDKs.{' '}
                <Link to="/privacy">Read our Privacy Policy</Link>.
              </p>
            </div>
          </div>
        </div>
      </section>
    </>
  )
}
