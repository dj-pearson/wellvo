/**
 * The caller's IP address, trusting forwarding headers only from a proxy that
 * really sits in front of this server.
 *
 * /redeem-code used to take CF-Connecting-IP, then X-Real-IP, then the first
 * X-Forwarded-For entry straight from the request. The container is also
 * published on the host's port 9000, and Traefik on the VPS accepts any Host
 * header, so a client that skipped Cloudflare could send a different
 * CF-Connecting-IP with every request (or none, which skipped the per-IP
 * check entirely) and the 30-failures-per-IP-per-hour pairing-code limit
 * never applied to it.
 *
 * Now:
 *   1. The socket peer (Deno.serve's info.remoteAddr, recorded by server.ts)
 *      is the starting point. It can't be forged.
 *   2. Forwarding headers are read only when that peer is a trusted proxy:
 *      private / loopback addresses (Traefik and the Docker network) or
 *      TRUSTED_PROXY_CIDRS.
 *   3. Traefik appends ITS peer to X-Forwarded-For, so the right-most entry is
 *      whoever connected to Traefik. CF-Connecting-IP is believed only when
 *      that hop is one of Cloudflare's published ranges (the orange-cloud
 *      path). Anyone else is identified by that hop itself.
 *
 * Returns null when no address is known (no peer, or a trusted proxy that
 * forwarded nothing); /redeem-code then applies only its per-user limit.
 */

const peers = new WeakMap<Request, string>();

/** Called by server.ts for every request with Deno's socket peer address. */
export function recordPeerAddress(req: Request, address: string | null | undefined): void {
  if (address) peers.set(req, address);
}

export function peerAddress(req: Request): string | null {
  return peers.get(req) ?? null;
}

// https://www.cloudflare.com/ips-v4 and /ips-v6 (stable for years; override
// with CLOUDFLARE_IP_RANGES if they ever change).
const CLOUDFLARE_RANGES = [
  "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22",
  "141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20",
  "197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
  "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22",
  "2400:cb00::/32", "2606:4700::/32", "2803:f800::/32", "2405:b500::/32",
  "2405:8100::/32", "2a06:98c0::/29", "2c0f:f248::/32",
];

// Loopback, RFC 1918, Docker's default pools, IPv6 ULA / link-local.
const PRIVATE_RANGES = [
  "127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
  "::1/128", "fc00::/7", "fe80::/10",
];

export interface ClientIpOptions {
  trustedProxies?: string[];
  cloudflareRanges?: string[];
}

function envList(name: string): string[] | undefined {
  try {
    // deno-lint-ignore no-explicit-any
    const raw = (globalThis as any).Deno?.env?.get(name);
    if (typeof raw !== "string" || raw.trim() === "") return undefined;
    return raw.split(",").map((s: string) => s.trim()).filter(Boolean);
  } catch {
    return undefined;
  }
}

/** The client IP for rate limiting (see the file comment). */
export function clientIp(req: Request, options: ClientIpOptions = {}): string | null {
  return resolveClientIp(peerAddress(req), req.headers, options);
}

/** Pure core of clientIp, for tests. */
export function resolveClientIp(
  peer: string | null,
  headers: Headers,
  options: ClientIpOptions = {},
): string | null {
  const trusted = options.trustedProxies ?? [...PRIVATE_RANGES, ...(envList("TRUSTED_PROXY_CIDRS") ?? [])];
  const cloudflare = options.cloudflareRanges ?? envList("CLOUDFLARE_IP_RANGES") ?? CLOUDFLARE_RANGES;

  const peerIp = peer ? normalizeIp(peer) : null;

  // Directly from the internet (or no peer known): the peer is the client.
  // No peer at all happens only outside Deno.serve; fall back to the old
  // header order there rather than to "no limit".
  if (peerIp && !inAnyRange(peerIp, trusted)) {
    // A request that reached us straight from Cloudflare (no Traefik).
    if (inAnyRange(peerIp, cloudflare)) {
      return headerIp(headers.get("CF-Connecting-IP")) ?? peerIp;
    }
    return peerIp;
  }

  // Behind a trusted proxy. The right-most X-Forwarded-For hop is the address
  // that proxy saw; only if that is Cloudflare do we believe Cloudflare's
  // header about the real client.
  const hop = lastForwardedHop(headers) ?? headerIp(headers.get("X-Real-IP"));
  if (hop) {
    if (inAnyRange(hop, cloudflare)) {
      return headerIp(headers.get("CF-Connecting-IP")) ?? hop;
    }
    return hop;
  }
  if (!peerIp) {
    return headerIp(headers.get("CF-Connecting-IP")) ?? headerIp(headers.get("X-Real-IP"));
  }
  // A trusted proxy that said nothing about its client. Keying on the proxy
  // itself would put every user in one bucket (30 wrong codes an hour would
  // lock everyone out), so report "unknown"; the per-user limit still holds.
  return null;
}

function lastForwardedHop(headers: Headers): string | null {
  const fwd = headers.get("X-Forwarded-For");
  if (!fwd) return null;
  const parts = fwd.split(",").map((p) => p.trim()).filter(Boolean);
  return parts.length ? headerIp(parts[parts.length - 1]) : null;
}

function headerIp(value: string | null): string | null {
  if (!value) return null;
  const ip = normalizeIp(value.trim());
  return ip && (parseV4(ip) !== null || parseV6(ip) !== null) ? ip : null;
}

/** Strips brackets, ports and the IPv4-mapped IPv6 prefix. */
export function normalizeIp(raw: string): string {
  let ip = raw.trim();
  if (ip.startsWith("[")) ip = ip.slice(1, ip.indexOf("]") > 0 ? ip.indexOf("]") : undefined);
  // "1.2.3.4:5678" (IPv4 with a port) — IPv6 has more than one colon.
  if (/^\d+\.\d+\.\d+\.\d+:\d+$/.test(ip)) ip = ip.slice(0, ip.lastIndexOf(":"));
  const lower = ip.toLowerCase();
  if (lower.startsWith("::ffff:") && parseV4(lower.slice(7)) !== null) return lower.slice(7);
  return lower;
}

export function inAnyRange(ip: string, cidrs: string[]): boolean {
  return cidrs.some((c) => inRange(ip, c));
}

export function inRange(ip: string, cidr: string): boolean {
  const [base, bitsRaw] = cidr.split("/");
  const v4 = parseV4(ip);
  const baseV4 = parseV4(base);
  if (v4 !== null && baseV4 !== null) {
    const bits = bitsRaw === undefined ? 32 : Number(bitsRaw);
    if (!(bits >= 0 && bits <= 32)) return false;
    if (bits === 0) return true;
    const mask = (0xffffffff << (32 - bits)) >>> 0;
    return ((v4 & mask) >>> 0) === ((baseV4 & mask) >>> 0);
  }
  const v6 = parseV6(ip);
  const baseV6 = parseV6(base);
  if (v6 === null || baseV6 === null) return false;
  const bits = bitsRaw === undefined ? 128 : Number(bitsRaw);
  if (!(bits >= 0 && bits <= 128)) return false;
  for (let i = 0; i < 8; i++) {
    const take = Math.max(0, Math.min(16, bits - i * 16));
    if (take === 0) break;
    const mask = (0xffff << (16 - take)) & 0xffff;
    if ((v6[i] & mask) !== (baseV6[i] & mask)) return false;
  }
  return true;
}

function parseV4(ip: string): number | null {
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(ip);
  if (!m) return null;
  const parts = m.slice(1).map(Number);
  if (parts.some((p) => p > 255)) return null;
  return ((parts[0] << 24) >>> 0) + (parts[1] << 16) + (parts[2] << 8) + parts[3];
}

function parseV6(ip: string): number[] | null {
  if (!ip.includes(":")) return null;
  const halves = ip.split("::");
  if (halves.length > 2) return null;
  const toGroups = (s: string) => (s === "" ? [] : s.split(":"));
  const head = toGroups(halves[0]);
  const tail = halves.length === 2 ? toGroups(halves[1]) : [];
  const missing = 8 - head.length - tail.length;
  if (halves.length === 1 && missing !== 0) return null;
  if (missing < 0) return null;
  const groups = [...head, ...Array(halves.length === 2 ? missing : 0).fill("0"), ...tail];
  if (groups.length !== 8) return null;
  const out: number[] = [];
  for (const g of groups) {
    if (!/^[0-9a-f]{1,4}$/.test(g)) return null;
    out.push(parseInt(g, 16));
  }
  return out;
}
