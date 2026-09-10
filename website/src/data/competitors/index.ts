import lifeAlert from './life-alert.json'
import life360 from './life360.json'
import snugSafety from './snug-safety.json'
import aloeCare from './aloe-care.json'
import lively from './lively.json'
import medicalGuardian from './medical-guardian.json'
import bayAlarmMedical from './bay-alarm-medical.json'
import appleWatch from './apple-watch.json'
import mobileHelp from './mobilehelp.json'
import checkinBee from './checkin-bee.json'

export interface FeatureRow {
  feature: string
  daily_ok: string
  competitor: string
  winner?: 'daily_ok' | 'competitor' | 'tie' | 'different'
}

export interface CompetitorFaq {
  q: string
  a: string
}

export interface CompetitorSource {
  title: string
  url: string
  accessed: string // YYYY-MM-DD
}

export interface CompetitorData {
  /** Slug used in the URL: /compare/daily-ok-vs-{slug}/ */
  slug: string
  /** Display name of the competitor. */
  name: string
  /** One-line category descriptor. */
  tagline: string
  /** Competitor's own homepage. */
  company_url: string
  /** Date the competitor data was last manually verified (YYYY-MM-DD). */
  last_verified: string
  /**
   * SERP title override (US-SEO008). Only needed when the default —
   * `Daily OK vs. {name}: Honest Comparison (2026)` — exceeds the ~60
   * characters Google renders before truncating. Apple Watch is the one
   * competitor whose display name is a phrase rather than a brand.
   */
  meta_title?: string
  /**
   * Hand-written SERP description, <=160 characters (US-SEO008).
   *
   * This used to be derived by taking the first two sentences of
   * daily_ok_verdict, which is prose written to be read on the page and has
   * no length ceiling — it produced descriptions of 225 to 407 characters, so
   * Google cut every one of them off mid-sentence. The snippet is the ad; it
   * gets written as one.
   */
  meta_description: string
  /** ~120-word hand-written TL;DR verdict, unique per page. */
  daily_ok_verdict: string
  /** 3–5 bullets: who should pick Daily OK. */
  best_for_daily_ok: string[]
  /** 3–5 bullets: who should pick the competitor. Honesty matters. */
  best_for_competitor: string[]
  /** Above-the-fold snapshot card. */
  snapshot: {
    starting_price: string
    starting_price_note: string
    contract: string
    platform: string
    fall_detection: string
    gps_tracking: string
    who_gets_alerts_first: string
    daily_check_in: string
  }
  /** 10–18 row feature comparison table. */
  feature_matrix: FeatureRow[]
  /** Pricing breakdown with 1-yr + 3-yr TCO. */
  pricing_breakdown: {
    monthly: string
    one_year_tco: string
    three_year_tco: string
  }
  /** Step-by-step guide to switch. Omit if not applicable. */
  migration_guide?: string[]
  /** 4–8 FAQs, rendered to a FAQPage schema. */
  faqs: CompetitorFaq[]
  /** Sources with URL + access date (for transparency and updates). */
  sources: CompetitorSource[]
}

export const competitors: CompetitorData[] = [
  lifeAlert as CompetitorData,
  life360 as CompetitorData,
  snugSafety as CompetitorData,
  aloeCare as CompetitorData,
  lively as CompetitorData,
  medicalGuardian as CompetitorData,
  bayAlarmMedical as CompetitorData,
  appleWatch as CompetitorData,
  mobileHelp as CompetitorData,
  checkinBee as CompetitorData,
]

export function getCompetitor(slug: string): CompetitorData | undefined {
  return competitors.find((c) => c.slug === slug)
}
