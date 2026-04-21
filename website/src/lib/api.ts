import { getSupabase } from './supabase'

const baseUrl = import.meta.env.VITE_EDGE_FUNCTIONS_URL

export class ApiError extends Error {
  status: number
  details?: unknown
  constructor(message: string, status: number, details?: unknown) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.details = details
  }
}

async function getAccessToken(): Promise<string> {
  const { data } = await getSupabase().auth.getSession()
  const token = data.session?.access_token
  if (!token) throw new ApiError('Not signed in', 401)
  return token
}

/**
 * Call an edge-functions endpoint with the current user's JWT.
 * Endpoints live at `${VITE_EDGE_FUNCTIONS_URL}/<path>`.
 */
export async function callEdge<T = unknown>(path: string, body?: unknown): Promise<T> {
  if (!baseUrl) {
    throw new ApiError('VITE_EDGE_FUNCTIONS_URL not configured', 500)
  }
  const token = await getAccessToken()
  const url = `${baseUrl.replace(/\/$/, '')}${path.startsWith('/') ? path : `/${path}`}`

  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  })

  const text = await res.text()
  const parsed = text ? safeJson(text) : null

  if (!res.ok) {
    const message =
      (parsed && typeof parsed === 'object' && 'error' in parsed && typeof parsed.error === 'string'
        ? parsed.error
        : null) ?? `Request failed (${res.status})`
    throw new ApiError(message, res.status, parsed)
  }

  return parsed as T
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text)
  } catch {
    return null
  }
}
