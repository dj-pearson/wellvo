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
  it('displays all three paid plan names', () => {
    renderPricing()
    expect(screen.getByText('Caregiver')).toBeInTheDocument()
    expect(screen.getByText('Family')).toBeInTheDocument()
    expect(screen.getByText('Family+')).toBeInTheDocument()
  })

  it('does not show a permanent Free tier', () => {
    renderPricing()
    // "Free Trial" CTA is allowed; bare "$0" price or "Free" plan name is not.
    expect(screen.queryByText('$0')).not.toBeInTheDocument()
  })

  it('displays correct monthly prices', () => {
    renderPricing()
    expect(screen.getByText('$3.99')).toBeInTheDocument()
    expect(screen.getByText('$6.99')).toBeInTheDocument()
    expect(screen.getByText('$9.99')).toBeInTheDocument()
  })

  it('displays correct yearly prices', () => {
    renderPricing()
    expect(screen.getByText('$29.99/year')).toBeInTheDocument()
    expect(screen.getByText('$49.99/year')).toBeInTheDocument()
    expect(screen.getByText('$79.99/year')).toBeInTheDocument()
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

  it('shows dementia-specific FAQ entry', () => {
    renderPricing()
    expect(
      screen.getByText('Which plan is right for a parent with dementia?')
    ).toBeInTheDocument()
  })
})
