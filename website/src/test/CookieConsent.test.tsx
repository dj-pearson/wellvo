import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { describe, it, expect, beforeEach } from 'vitest'
import CookieConsent from '../components/CookieConsent'

describe('CookieConsent', () => {
  beforeEach(() => {
    try {
      localStorage.clear()
    } catch {
      // storage unavailable: banner still shows with no stored choice
    }
  })

  it('gives Decline and Accept equal visual weight', async () => {
    render(
      <MemoryRouter>
        <CookieConsent />
      </MemoryRouter>
    )
    const decline = await screen.findByRole('button', { name: 'Decline' })
    const accept = screen.getByRole('button', { name: 'Accept analytics' })
    expect(decline.className).toBe(accept.className)
  })
})
