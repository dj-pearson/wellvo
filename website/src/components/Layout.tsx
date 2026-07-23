import { Outlet } from 'react-router-dom'
import Header from './Header'
import Footer from './Footer'
import CookieConsent from './CookieConsent'

export default function Layout() {
  return (
    <>
      <a href="#main-content" className="skip-link">Skip to main content</a>
      <Header />
      {/* tabIndex=-1 makes this a programmatic focus target for the skip link
          and for RouteFocusManager on SPA navigation (WCAG 2.4.3). */}
      <main id="main-content" tabIndex={-1}>
        <Outlet />
      </main>
      <Footer />
      <CookieConsent />
    </>
  )
}
