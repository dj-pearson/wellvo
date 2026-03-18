/**
 * In-memory rate limiter for edge function endpoints.
 * Uses a sliding window counter per user+endpoint key.
 */

interface RateLimitEntry {
  count: number;
  windowStart: number;
}

const store = new Map<string, RateLimitEntry>();

// Clean up expired entries every 5 minutes
setInterval(() => {
  const now = Date.now();
  for (const [key, entry] of store) {
    if (now - entry.windowStart > 120_000) {
      store.delete(key);
    }
  }
}, 300_000);

// Per-endpoint limits (requests per minute)
const ENDPOINT_LIMITS: Record<string, number> = {
  "/invite-receiver": 5,
  "/on-demand-checkin": 10,
};

const DEFAULT_LIMIT = 30; // requests per minute
const WINDOW_MS = 60_000; // 1 minute

export interface RateLimitResult {
  allowed: boolean;
  retryAfterSeconds?: number;
}

/**
 * Check rate limit for a given user ID and endpoint path.
 * Returns { allowed: true } if within limits, or { allowed: false, retryAfterSeconds } if exceeded.
 */
export function checkRateLimit(userId: string, endpoint: string): RateLimitResult {
  const limit = ENDPOINT_LIMITS[endpoint] ?? DEFAULT_LIMIT;
  const key = `${userId}:${endpoint}`;
  const now = Date.now();

  const entry = store.get(key);

  if (!entry || now - entry.windowStart >= WINDOW_MS) {
    // New window
    store.set(key, { count: 1, windowStart: now });
    return { allowed: true };
  }

  if (entry.count >= limit) {
    const retryAfterSeconds = Math.ceil((entry.windowStart + WINDOW_MS - now) / 1000);
    return { allowed: false, retryAfterSeconds };
  }

  entry.count++;
  return { allowed: true };
}
