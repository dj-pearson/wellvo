import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { describe, it, expect } from 'vitest'
import Pricing from '../pages/Pricing'
import { APP_STORE_URL } from '../lib/appStore'

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

  it('leads the yearly option with its effective monthly price', () => {
    renderPricing()
    expect(screen.getByText('$2.50/mo')).toBeInTheDocument()
    expect(screen.getByText('$4.17/mo')).toBeInTheDocument()
    expect(screen.getByText('$6.67/mo')).toBeInTheDocument()
    expect(screen.getAllByText(/billed yearly/)).toHaveLength(3)
  })

  it('says where each plan CTA goes', () => {
    renderPricing()
    const ctas = screen.getAllByRole('link', { name: /Start free trial on the App Store/ })
    expect(ctas).toHaveLength(3)
    for (const cta of ctas) expect(cta).toHaveAttribute('href', APP_STORE_URL)
  })

  it('offers a desktop install path: App Store badge and QR code', () => {
    renderPricing()
    expect(screen.getByRole('link', { name: /Download on the App Store/ })).toHaveAttribute(
      'href',
      APP_STORE_URL,
    )
    expect(screen.getByAltText(/QR code that opens Daily OK on the App Store/)).toHaveAttribute(
      'src',
      '/app-store-qr.svg',
    )
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

  it('states a 7-day trial on monthly and yearly, cancelled via Apple ID', () => {
    renderPricing()
    expect(screen.getByText(/7-day free trial, on both monthly and yearly billing/)).toBeInTheDocument()
    expect(screen.queryByText(/Google Play/)).not.toBeInTheDocument()
  })

  it('shows dementia-specific FAQ entry', () => {
    renderPricing()
    expect(
      screen.getByText('Which plan is right for a parent with dementia?')
    ).toBeInTheDocument()
  })
})
