import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { describe, it, expect } from 'vitest'
import App from '../App'

function renderApp(initialRoute = '/') {
  return render(
    <MemoryRouter initialEntries={[initialRoute]}>
      <App />
    </MemoryRouter>
  )
}

describe('App routing', () => {
  it('renders home page at /', async () => {
    renderApp('/')
    expect(await screen.findByText(/know your loved ones are OK/i)).toBeInTheDocument()
  })

  it('renders pricing page at /pricing', async () => {
    renderApp('/pricing')
    expect(await screen.findByText(/Simple, Transparent Pricing/i)).toBeInTheDocument()
  })

  it('renders support page at /support', async () => {
    renderApp('/support')
    expect(await screen.findByText(/Email Support/i)).toBeInTheDocument()
  })

  it('renders privacy page at /privacy', async () => {
    renderApp('/privacy')
    expect(await screen.findByRole('heading', { name: /Privacy Policy/i, level: 1 })).toBeInTheDocument()
  })

  it('renders terms page at /terms', async () => {
    renderApp('/terms')
    expect(await screen.findByRole('heading', { name: /Terms of Use/i, level: 1 })).toBeInTheDocument()
  })

  it('renders 404 for unknown routes', async () => {
    renderApp('/unknown-path')
    expect(await screen.findByText(/Page not found/i)).toBeInTheDocument()
  })
})
