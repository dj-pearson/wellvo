import { render, screen, fireEvent } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
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
    expect(screen.getByText('Wellvo')).toBeInTheDocument()
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
})
