import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { describe, it, expect } from 'vitest'
import Pricing from '../pages/Pricing'

function renderPricing() {
  return render(
    <MemoryRouter>
      <Pricing />
    </MemoryRouter>
  )
}

describe('Pricing page', () => {
  it('displays all three plan names', () => {
    renderPricing()
    expect(screen.getByText('Free')).toBeInTheDocument()
    expect(screen.getByText('Family')).toBeInTheDocument()
    expect(screen.getByText('Family+')).toBeInTheDocument()
  })

  it('displays correct prices', () => {
    renderPricing()
    expect(screen.getByText('$0')).toBeInTheDocument()
    expect(screen.getByText('$4.99')).toBeInTheDocument()
    expect(screen.getByText('$7.99')).toBeInTheDocument()
  })

  it('shows add-on section', () => {
    renderPricing()
    expect(screen.getByText('Add-Ons')).toBeInTheDocument()
    expect(screen.getByText('Additional Receiver')).toBeInTheDocument()
    expect(screen.getByText('Additional Viewer')).toBeInTheDocument()
  })

  it('shows FAQ section', () => {
    renderPricing()
    expect(screen.getByText('Frequently Asked Questions')).toBeInTheDocument()
    expect(screen.getByText('Who pays for the subscription?')).toBeInTheDocument()
  })
})
