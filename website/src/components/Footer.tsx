import { Link } from 'react-router-dom'
import { APP_STORE_URL } from './SEO'
import './Footer.css'

export default function Footer() {
  const currentYear = new Date().getFullYear()

  return (
    <footer className="footer">
      <div className="container footer-inner">
        <div className="footer-grid">
          <div className="footer-brand">
            <div className="footer-logo">
              <div className="logo-icon">D</div>
              <span className="logo-text">Daily OK</span>
            </div>
            <p className="footer-tagline">One tap. Peace of mind.</p>
            <p className="footer-desc">
              The simplest senior check-in app — a once-a-day &quot;I&apos;m OK&quot; for your
              aging parent, with alerts if they miss it. Works for teens and any loved one, too.
            </p>
          </div>

          <div className="footer-col">
            <h4>Product</h4>
            <Link to="/pricing/">Pricing</Link>
            <Link to="/#features">Features</Link>
            <Link to="/#how-it-works">How It Works</Link>
            <Link to="/compare/">Compare</Link>
            <a href={APP_STORE_URL} target="_blank" rel="noopener noreferrer">Download App</a>
          </div>

          <div className="footer-col">
            <h4>Senior Check-In</h4>
            <Link to="/check-in-app-for-elderly/">Check-In App for Elderly</Link>
            <Link to="/daily-check-in-app-for-seniors/">Daily Check-In for Seniors</Link>
            <Link to="/peace-of-mind-app-for-elderly-parents/">Peace of Mind for Parents</Link>
            <Link to="/elderly-care/">Elderly Parent Care</Link>
            <Link to="/child-safety/">Child &amp; Teen Safety</Link>
          </div>

          <div className="footer-col">
            <h4>Support</h4>
            <Link to="/blog/">Blog</Link>
            <Link to="/support/">Help Center</Link>
            <a href="mailto:support@dailyok.net">Contact Us</a>
          </div>

          <div className="footer-col">
            <h4>Legal</h4>
            <Link to="/privacy/">Privacy Policy</Link>
            <Link to="/terms/">Terms of Use</Link>
            <Link to="/cookies/">Cookie Notice</Link>
            <Link to="/dmca/">DMCA Policy</Link>
            <Link to="/accessibility/">Accessibility</Link>
          </div>
        </div>

        <div className="footer-bottom">
          <p>
            &copy; {currentYear} Pearson Media LLC d/b/a Daily OK. All rights reserved.
            <br />
            <span className="footer-address">
              Pearson Media LLC, 7889 Beechtree Ln, West Des Moines, IA 50266, USA &middot;{' '}
              <a href="mailto:support@dailyok.net">support@dailyok.net</a>
            </span>
          </p>
          <p className="footer-note">
            Available on the{' '}
            <a href={APP_STORE_URL} target="_blank" rel="noopener noreferrer">App Store</a> for iPhone.
            {' · '}
            <Link to="/admin/" className="footer-admin-link">Admin</Link>
          </p>
        </div>
      </div>
    </footer>
  )
}
