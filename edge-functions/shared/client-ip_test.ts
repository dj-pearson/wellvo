import { assertEquals } from "std/assert/mod.ts";
import { inRange, normalizeIp, resolveClientIp } from "./client-ip.ts";

// The pairing-code per-IP limit keyed on whatever CF-Connecting-IP a caller
// sent. A client that skipped Cloudflare (the origin is reachable directly)
// picked a new "IP" per request, so the limit never applied to it.

const CF_EDGE = "172.70.1.2"; // inside 172.64.0.0/13
const TRAEFIK = "172.18.0.5"; // Docker network
const opts = { trustedProxies: ["127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fc00::/7"] };

function h(entries: Record<string, string>): Headers {
  return new Headers(entries);
}

Deno.test("Cloudflare → Traefik → us: the real client from CF-Connecting-IP", () => {
  const ip = resolveClientIp(TRAEFIK, h({
    "CF-Connecting-IP": "203.0.113.9",
    "X-Forwarded-For": `203.0.113.9, ${CF_EDGE}`,
  }), opts);
  assertEquals(ip, "203.0.113.9");
});

Deno.test("Traefik hit directly (no Cloudflare): a forged CF-Connecting-IP is ignored", () => {
  const ip = resolveClientIp(TRAEFIK, h({
    "CF-Connecting-IP": "1.1.1.1",
    "X-Forwarded-For": "9.9.9.9, 198.51.100.7",
  }), opts);
  assertEquals(ip, "198.51.100.7");
});

Deno.test("Port 9000 hit directly: headers are ignored, the socket peer is the client", () => {
  const ip = resolveClientIp("198.51.100.7", h({
    "CF-Connecting-IP": "1.1.1.1",
    "X-Real-IP": "2.2.2.2",
    "X-Forwarded-For": "3.3.3.3",
  }), opts);
  assertEquals(ip, "198.51.100.7");
});

Deno.test("Port 9000 hit directly with no headers: still limited, never null", () => {
  assertEquals(resolveClientIp("198.51.100.7", h({}), opts), "198.51.100.7");
});

Deno.test("Cloudflare straight to us (no Traefik) is believed", () => {
  const ip = resolveClientIp(CF_EDGE, h({ "CF-Connecting-IP": "203.0.113.9" }), opts);
  assertEquals(ip, "203.0.113.9");
});

Deno.test("Garbage in forwarding headers never becomes the key", () => {
  const ip = resolveClientIp(TRAEFIK, h({
    "CF-Connecting-IP": "not-an-ip",
    "X-Forwarded-For": `x, ${CF_EDGE}`,
  }), opts);
  assertEquals(ip, CF_EDGE);
});

Deno.test("No peer known (outside Deno.serve): old header order", () => {
  assertEquals(resolveClientIp(null, h({ "CF-Connecting-IP": "203.0.113.9" }), opts), "203.0.113.9");
  assertEquals(resolveClientIp(null, h({}), opts), null);
});

Deno.test("Trusted proxy that forwarded nothing: unknown, not the proxy's own address", () => {
  // Keying on the proxy would put every user in one bucket.
  assertEquals(resolveClientIp(TRAEFIK, h({ "CF-Connecting-IP": "1.1.1.1" }), opts), null);
});

Deno.test("IPv6 and IPv4-mapped peers", () => {
  assertEquals(normalizeIp("::FFFF:198.51.100.7"), "198.51.100.7");
  assertEquals(normalizeIp("[2001:db8::1]"), "2001:db8::1");
  assertEquals(inRange("2606:4700:10::6816:1", "2606:4700::/32"), true);
  assertEquals(inRange("2606:4701::1", "2606:4700::/32"), false);
  assertEquals(inRange("2a06:98c7::1", "2a06:98c0::/29"), true);
  assertEquals(inRange("2a06:98c8::1", "2a06:98c0::/29"), false);
  const ip = resolveClientIp("2001:db8::7", h({ "CF-Connecting-IP": "1.1.1.1" }), opts);
  assertEquals(ip, "2001:db8::7");
});

Deno.test("CIDR edges", () => {
  assertEquals(inRange("172.31.255.255", "172.16.0.0/12"), true);
  assertEquals(inRange("172.32.0.0", "172.16.0.0/12"), false);
  assertEquals(inRange("104.23.255.1", "104.16.0.0/13"), true);
  assertEquals(inRange("104.24.0.1", "104.16.0.0/13"), false);
});
