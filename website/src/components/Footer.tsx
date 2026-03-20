import { Link } from 'react-router-dom'
import './Footer.css'

export default function Footer() {
  const currentYear = new Date().getFullYear()

  return (
    <footer className="footer">
      <div className="container footer-inner">
        <div className="footer-grid">
          <div className="footer-brand">
            <div className="footer-logo">
              <div className="logo-icon">W</div>
              <span className="logo-text">Wellvo</span>
            </div>
            <p className="footer-tagline">One tap. Peace of mind.</p>
            <p className="footer-desc">
              The simplest daily check-in app for families who care about each other's wellness.
            </p>
          </div>

          <div className="footer-col">
            <h4>Product</h4>
            <Link to="/pricing">Pricing</Link>
            <Link to="/#features">Features</Link>
            <Link to="/#how-it-works">How It Works</Link>
          </div>

          <div className="footer-col">
            <h4>Support</h4>
            <Link to="/support">Help Center</Link>
            <a href="mailto:support@wellvo.net">Contact Us</a>
          </div>

          <div className="footer-col">
            <h4>Legal</h4>
            <Link to="/privacy">Privacy Policy</Link>
            <Link to="/terms">Terms of Use</Link>
            <Link to="/accessibility">Accessibility</Link>
          </div>
        </div>

        <div className="footer-bottom">
          <p>&copy; {currentYear} Wellvo. All rights reserved.</p>
          <p className="footer-note">
            Available on the App Store for iPhone.
          </p>
        </div>
      </div>
    </footer>
  )
}
