import { useState, useEffect, useRef } from 'react'
import { Link, useLocation } from 'react-router-dom'
import { Menu, X } from 'lucide-react'
import { APP_STORE_URL } from './SEO'
import './Header.css'

export default function Header() {
  const location = useLocation()
  // The menu remembers which pathname it was opened on, so any navigation
  // (nav links, back/forward, in-page links) closes it without an effect.
  const [openedOn, setOpenedOn] = useState<string | null>(null)
  const menuOpen = openedOn === location.pathname
  const setMenuOpen = (open: boolean) => setOpenedOn(open ? location.pathname : null)
  const toggleRef = useRef<HTMLButtonElement>(null)

  const isActive = (path: string) => location.pathname === path

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && menuOpen) {
        setOpenedOn(null)
        // Focus was likely inside the menu that's now hidden — hand it back
        // to the control that opened it.
        toggleRef.current?.focus()
      }
    }
    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [menuOpen])

  return (
    <header className="header">
      <div className="container header-inner">
        <Link to="/" className="logo">
          <img src="/Logo.svg" alt="Daily OK" className="logo-img" width={108} height={36} />
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
            to="/what-to-do/"
            className={`nav-link ${isActive('/what-to-do') ? 'active' : ''}`}
            aria-current={isActive('/what-to-do') ? 'page' : undefined}
            onClick={() => setMenuOpen(false)}
          >
            Not Answering?
          </Link>
          <Link
            to="/compare/"
            className={`nav-link ${isActive('/compare') ? 'active' : ''}`}
            aria-current={isActive('/compare') ? 'page' : undefined}
            onClick={() => setMenuOpen(false)}
          >
            Compare
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
          ref={toggleRef}
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
