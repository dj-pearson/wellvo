import { render, screen, fireEvent } from '@testing-library/react'
import { MemoryRouter, useNavigate } from 'react-router-dom'
import { describe, it, expect } from 'vitest'
import Header from '../components/Header'

function renderHeader() {
  return render(
    <MemoryRouter>
      <Header />
    </MemoryRouter>
  )
}

describe('Header component', () => {
  it('renders logo text', () => {
    renderHeader()
    expect(screen.getByAltText('Daily OK')).toBeInTheDocument()
  })

  it('renders navigation links', () => {
    renderHeader()
    expect(screen.getByText('Home')).toBeInTheDocument()
    expect(screen.getByText('Pricing')).toBeInTheDocument()
    expect(screen.getByText('Support')).toBeInTheDocument()
  })

  it('has download app CTA', () => {
    renderHeader()
    expect(screen.getByText('Download App')).toBeInTheDocument()
  })

  it('toggles mobile menu', () => {
    renderHeader()
    const toggleButton = screen.getByLabelText('Toggle menu')
    expect(toggleButton).toHaveAttribute('aria-expanded', 'false')
    fireEvent.click(toggleButton)
    expect(toggleButton).toHaveAttribute('aria-expanded', 'true')
  })

  it('closes the menu on route change', () => {
    function GoToPricing() {
      const navigate = useNavigate()
      return <button onClick={() => void navigate('/pricing/')}>go</button>
    }
    render(
      <MemoryRouter initialEntries={['/']}>
        <Header />
        <GoToPricing />
      </MemoryRouter>
    )
    const toggleButton = screen.getByLabelText('Toggle menu')
    fireEvent.click(toggleButton)
    expect(toggleButton).toHaveAttribute('aria-expanded', 'true')
    fireEvent.click(screen.getByText('go'))
    expect(toggleButton).toHaveAttribute('aria-expanded', 'false')
  })

  it('returns focus to the toggle when Escape closes the menu', () => {
    renderHeader()
    const toggleButton = screen.getByLabelText('Toggle menu')
    fireEvent.click(toggleButton)
    screen.getByText('Pricing').focus()
    fireEvent.keyDown(document, { key: 'Escape' })
    expect(toggleButton).toHaveAttribute('aria-expanded', 'false')
    expect(toggleButton).toHaveFocus()
  })

  it('gives the logo intrinsic dimensions', () => {
    renderHeader()
    const logo = screen.getByAltText('Daily OK')
    expect(logo).toHaveAttribute('width', '108')
    expect(logo).toHaveAttribute('height', '36')
  })
})
