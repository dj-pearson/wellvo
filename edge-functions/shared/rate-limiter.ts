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

// Service role rate limits (separate from user limits)
const SERVICE_ROLE_GLOBAL_LIMIT = 200; // requests per minute across all endpoints
const SERVICE_ROLE_KEY = "__service_role__";

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

/**
 * Check rate limit for service role requests.
 * Uses a global limit across all endpoints to prevent abuse of a leaked service role key.
 */
export function checkServiceRoleRateLimit(endpoint: string): RateLimitResult {
  const now = Date.now();

  // Global service role limit
  const globalKey = `${SERVICE_ROLE_KEY}:__global__`;
  const globalEntry = store.get(globalKey);

  if (!globalEntry || now - globalEntry.windowStart >= WINDOW_MS) {
    store.set(globalKey, { count: 1, windowStart: now });
  } else if (globalEntry.count >= SERVICE_ROLE_GLOBAL_LIMIT) {
    const retryAfterSeconds = Math.ceil((globalEntry.windowStart + WINDOW_MS - now) / 1000);
    return { allowed: false, retryAfterSeconds };
  } else {
    globalEntry.count++;
  }

  // Per-endpoint service role limit
  const endpointKey = `${SERVICE_ROLE_KEY}:${endpoint}`;
  const endpointLimit = ENDPOINT_LIMITS[endpoint] ? ENDPOINT_LIMITS[endpoint] * 4 : DEFAULT_LIMIT * 2;
  const endpointEntry = store.get(endpointKey);

  if (!endpointEntry || now - endpointEntry.windowStart >= WINDOW_MS) {
    store.set(endpointKey, { count: 1, windowStart: now });
    return { allowed: true };
  }

  if (endpointEntry.count >= endpointLimit) {
    const retryAfterSeconds = Math.ceil((endpointEntry.windowStart + WINDOW_MS - now) / 1000);
    return { allowed: false, retryAfterSeconds };
  }

  endpointEntry.count++;
  return { allowed: true };
}
