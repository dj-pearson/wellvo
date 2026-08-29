import { useState, useEffect } from 'react'
import { Link, useLocation } from 'react-router-dom'
import { Menu, X } from 'lucide-react'
import { APP_STORE_URL } from './SEO'
import './Header.css'

export default function Header() {
  const [menuOpen, setMenuOpen] = useState(false)
  const location = useLocation()

  const isActive = (path: string) => location.pathname === path

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && menuOpen) {
        setMenuOpen(false)
      }
    }
    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [menuOpen])

  return (
    <header className="header">
      <div className="container header-inner">
        <Link to="/" className="logo">
          <img src="/Logo.svg" alt="Daily OK" style={{ height: '36px', width: 'auto' }} />
        </Link>

        <nav id="primary-navigation" className={`nav ${menuOpen ? 'nav-open' : ''}`} role="navigation" aria-label="Main navigation">
          <Link
            to="/"
            className={`nav-link ${isActive('/') ? 'active' : ''}`}
            aria-current={isActive('/') ? 'page' : undefined}
            onClick={() => setMenuOpen(false)}
          >
            Home
          </Link>
          <Link
            to="/elderly-care/"
            className={`nav-link ${isActive('/elderly-care') ? 'active' : ''}`}
            aria-current={isActive('/elderly-care') ? 'page' : undefined}
            onClick={() => setMenuOpen(false)}
          >
            For Seniors
          </Link>
          <Link
            to="/pricing/"
            className={`nav-link ${isActive('/pricing') ? 'active' : ''}`}
            aria-current={isActive('/pricing') ? 'page' : undefined}
            onClick={() => setMenuOpen(false)}
          >
            Pricing
          </Link>
          <Link
            to="/blog/"
            className={`nav-link ${location.pathname.startsWith('/blog') ? 'active' : ''}`}
            aria-current={location.pathname.startsWith('/blog') ? 'page' : undefined}
            onClick={() => setMenuOpen(false)}
          >
            Blog
          </Link>
          <Link
            to="/support/"
            className={`nav-link ${isActive('/support') ? 'active' : ''}`}
            aria-current={isActive('/support') ? 'page' : undefined}
            onClick={() => setMenuOpen(false)}
          >
            Support
          </Link>
          <a
            href={APP_STORE_URL}
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
          aria-controls="primary-navigation"
        >
          {menuOpen ? <X size={24} /> : <Menu size={24} />}
        </button>
      </div>
    </header>
  )
}
