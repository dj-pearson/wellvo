import { useState } from 'react'
import { Link, useLocation } from 'react-router-dom'
import { Menu, X } from 'lucide-react'
import './Header.css'

export default function Header() {
  const [menuOpen, setMenuOpen] = useState(false)
  const location = useLocation()

  const isActive = (path: string) => location.pathname === path

  return (
    <header className="header">
      <div className="container header-inner">
        <Link to="/" className="logo">
          <img src="/Logo.svg" alt="Wellvo" style={{ height: '36px', width: 'auto' }} />
        </Link>

        <nav className={`nav ${menuOpen ? 'nav-open' : ''}`} role="navigation" aria-label="Main navigation">
          <Link
            to="/"
            className={`nav-link ${isActive('/') ? 'active' : ''}`}
            aria-current={isActive('/') ? 'page' : undefined}
            onClick={() => setMenuOpen(false)}
          >
            Home
          </Link>
          <Link
            to="/pricing"
            className={`nav-link ${isActive('/pricing') ? 'active' : ''}`}
            aria-current={isActive('/pricing') ? 'page' : undefined}
            onClick={() => setMenuOpen(false)}
          >
            Pricing
          </Link>
          <Link
            to="/support"
            className={`nav-link ${isActive('/support') ? 'active' : ''}`}
            aria-current={isActive('/support') ? 'page' : undefined}
            onClick={() => setMenuOpen(false)}
          >
            Support
          </Link>
          <a
            href="https://apps.apple.com/app/wellvo"
            className="btn btn-primary nav-cta"
            target="_blank"
            rel="noopener noreferrer"
          >
            Download App
          </a>
        </nav>

        <button
          className="menu-toggle"
          onClick={() => setMenuOpen(!menuOpen)}
          aria-label="Toggle menu"
          aria-expanded={menuOpen}
        >
          {menuOpen ? <X size={24} /> : <Menu size={24} />}
        </button>
      </div>
    </header>
  )
}
