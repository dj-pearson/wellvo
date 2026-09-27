/**
 * Verification of data the App Store signs (US-EDGE005).
 *
 * StoreKit 2 transactions, renewal info and App Store Server Notifications v2
 * all arrive as a compact JWS whose header carries the signing certificate
 * chain in `x5c` (leaf, Apple WWDR intermediate, Apple Root CA - G3). A payload
 * is only trusted when:
 *   1. the chain has exactly three certificates;
 *   2. the last one is byte-for-byte Apple Root CA - G3 (pinned by SHA-256
 *      fingerprint, so a self-made root with the same name is refused);
 *   3. each certificate is signed by the next one (ECDSA, WebCrypto);
 *   4. the leaf and intermediate carry Apple's marker extensions
 *      (1.2.840.113635.100.6.11.1 and 1.2.840.113635.100.6.2.1), as Apple's
 *      own App Store Server Library requires;
 *   5. the JWS itself (ES256) verifies with the leaf's public key;
 *   6. the leaf and intermediate were valid when Apple signed the payload
 *      (`signedDate`), which may not be in the future.
 *
 * Pure WebCrypto and a minimal DER reader: no Deno-only or Node-only APIs, so
 * the same file runs under `deno test` and under Node for the fixture test.
 */

/** SHA-256 of the DER of "Apple Root CA - G3". Also published by Apple. */
export const APPLE_ROOT_CA_G3_SHA256 =
  "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";

const OID_ECDSA_SHA256 = "1.2.840.10045.4.3.2";
const OID_ECDSA_SHA384 = "1.2.840.10045.4.3.3";
const OID_P256 = "1.2.840.10045.3.1.7";
const OID_P384 = "1.3.132.0.34";

// DER encodings (tag 06, length 0A) of Apple's marker extension OIDs.
const APPLE_LEAF_MARKER = new Uint8Array([0x06, 0x0a, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x06, 0x0b, 0x01]);
const APPLE_INTERMEDIATE_MARKER = new Uint8Array([0x06, 0x0a, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x06, 0x02, 0x01]);

export class AppStoreJWSError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AppStoreJWSError";
  }
}

// ---------------------------------------------------------------------------
// Encoding helpers
// ---------------------------------------------------------------------------

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function base64UrlToBytes(b64url: string): Uint8Array {
  let b64 = b64url.replace(/-/g, "+").replace(/_/g, "/");
  while (b64.length % 4 !== 0) b64 += "=";
  return base64ToBytes(b64);
}

/** A standalone ArrayBuffer copy, which every TypeScript lib accepts as BufferSource. */
function ab(u: Uint8Array): ArrayBuffer {
  return u.slice().buffer as ArrayBuffer;
}

function toHex(bytes: ArrayBuffer | Uint8Array): string {
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  return Array.from(u8).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function contains(haystack: Uint8Array, needle: Uint8Array): boolean {
  outer: for (let i = 0; i + needle.length <= haystack.length; i++) {
    for (let j = 0; j < needle.length; j++) {
      if (haystack[i + j] !== needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Minimal DER reader (enough for X.509 certificates and ECDSA signatures)
// ---------------------------------------------------------------------------

interface Tlv {
  tag: number;
  /** Offset of the tag byte. */
  start: number;
  /** Offset of the first content byte. */
  contentStart: number;
  /** Offset just past the content. */
  end: number;
}

function readTlv(buf: Uint8Array, offset: number): Tlv {
  if (offset + 2 > buf.length) throw new AppStoreJWSError("Truncated DER");
  const tag = buf[offset];
  let len = buf[offset + 1];
  let p = offset + 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n === 0 || n > 4 || p + n > buf.length) throw new AppStoreJWSError("Bad DER length");
    len = 0;
    for (let i = 0; i < n; i++) len = (len * 256) + buf[p + i];
    p += n;
  }
  if (p + len > buf.length) throw new AppStoreJWSError("Truncated DER");
  return { tag, start: offset, contentStart: p, end: p + len };
}

function children(buf: Uint8Array, parent: Tlv): Tlv[] {
  const out: Tlv[] = [];
  let p = parent.contentStart;
  while (p < parent.end) {
    const t = readTlv(buf, p);
    out.push(t);
    p = t.end;
  }
  return out;
}

function decodeOid(bytes: Uint8Array): string {
  if (bytes.length === 0) return "";
  const parts: number[] = [Math.floor(bytes[0] / 40), bytes[0] % 40];
  let value = 0;
  for (let i = 1; i < bytes.length; i++) {
    value = (value * 128) + (bytes[i] & 0x7f);
    if (!(bytes[i] & 0x80)) {
      parts.push(value);
      value = 0;
    }
  }
  return parts.join(".");
}

function decodeTime(buf: Uint8Array, t: Tlv): Date {
  const s = new TextDecoder().decode(buf.slice(t.contentStart, t.end));
  // UTCTime YYMMDDHHMMSSZ (tag 0x17) or GeneralizedTime YYYYMMDDHHMMSSZ (0x18)
  let year: number;
  let rest: string;
  if (t.tag === 0x17) {
    const yy = parseInt(s.slice(0, 2), 10);
    year = yy >= 50 ? 1900 + yy : 2000 + yy;
    rest = s.slice(2);
  } else if (t.tag === 0x18) {
    year = parseInt(s.slice(0, 4), 10);
    rest = s.slice(4);
  } else {
    throw new AppStoreJWSError("Bad certificate time");
  }
  const month = parseInt(rest.slice(0, 2), 10) - 1;
  const day = parseInt(rest.slice(2, 4), 10);
  const hour = parseInt(rest.slice(4, 6), 10);
  const min = parseInt(rest.slice(6, 8), 10);
  const sec = parseInt(rest.slice(8, 10), 10) || 0;
  return new Date(Date.UTC(year, month, day, hour, min, sec));
}

interface ParsedCert {
  der: Uint8Array;
  tbs: Uint8Array;
  signatureOid: string;
  signature: Uint8Array;
  spki: Uint8Array;
  curveOid: string;
  notBefore: Date;
  notAfter: Date;
}

function parseCertificate(der: Uint8Array): ParsedCert {
  const cert = readTlv(der, 0);
  const [tbsTlv, sigAlgTlv, sigTlv] = children(der, cert);
  if (!tbsTlv || !sigAlgTlv || !sigTlv || sigTlv.tag !== 0x03) {
    throw new AppStoreJWSError("Malformed certificate");
  }
  const sigAlgOidTlv = children(der, sigAlgTlv)[0];
  const signatureOid = decodeOid(der.slice(sigAlgOidTlv.contentStart, sigAlgOidTlv.end));
  // BIT STRING: first content byte is the unused-bits count (0 here).
  const signature = der.slice(sigTlv.contentStart + 1, sigTlv.end);

  const tbsFields = children(der, tbsTlv);
  // An explicit [0] version tag shifts every later field by one.
  const base = tbsFields[0].tag === 0xa0 ? 1 : 0;
  const validity = tbsFields[base + 3];
  const spkiTlv = tbsFields[base + 5];
  if (!validity || !spkiTlv) throw new AppStoreJWSError("Malformed certificate");
  const [nb, na] = children(der, validity);
  const spkiAlg = children(der, children(der, spkiTlv)[0]);
  const curveOid = spkiAlg[1] ? decodeOid(der.slice(spkiAlg[1].contentStart, spkiAlg[1].end)) : "";

  return {
    der,
    tbs: der.slice(tbsTlv.start, tbsTlv.end),
    signatureOid,
    signature,
    spki: der.slice(spkiTlv.start, spkiTlv.end),
    curveOid,
    notBefore: decodeTime(der, nb),
    notAfter: decodeTime(der, na),
  };
}

/** DER ECDSA-Sig-Value (SEQUENCE { r, s }) → IEEE P1363 r||s for WebCrypto. */
function ecdsaDerToRaw(sig: Uint8Array, size: number): Uint8Array {
  const seq = readTlv(sig, 0);
  const [r, s] = children(sig, seq);
  const out = new Uint8Array(size * 2);
  const put = (t: Tlv, at: number) => {
    let bytes = sig.slice(t.contentStart, t.end);
    while (bytes.length > size && bytes[0] === 0) bytes = bytes.slice(1);
    if (bytes.length > size) throw new AppStoreJWSError("Bad ECDSA signature");
    out.set(bytes, at + (size - bytes.length));
  };
  put(r, 0);
  put(s, size);
  return out;
}

function curveFor(oid: string): { namedCurve: string; size: number } {
  if (oid === OID_P256) return { namedCurve: "P-256", size: 32 };
  if (oid === OID_P384) return { namedCurve: "P-384", size: 48 };
  throw new AppStoreJWSError("Unsupported key curve");
}

function importSpki(cert: ParsedCert): Promise<CryptoKey> {
  const { namedCurve } = curveFor(cert.curveOid);
  return crypto.subtle.importKey("spki", ab(cert.spki), { name: "ECDSA", namedCurve }, false, ["verify"]);
}

async function verifyIssuedBy(child: ParsedCert, issuer: ParsedCert): Promise<boolean> {
  const hash = child.signatureOid === OID_ECDSA_SHA256
    ? "SHA-256"
    : child.signatureOid === OID_ECDSA_SHA384
    ? "SHA-384"
    : null;
  if (!hash) return false;
  const { size } = curveFor(issuer.curveOid);
  const key = await importSpki(issuer);
  return crypto.subtle.verify(
    { name: "ECDSA", hash },
    key,
    ab(ecdsaDerToRaw(child.signature, size)),
    ab(child.tbs),
  );
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export interface VerifyOptions {
  /** Pinned root fingerprint (hex SHA-256 of DER). Tests pass their own. */
  rootSha256?: string;
  /** Clock, for tests. */
  now?: Date;
}

/**
 * Verify an App Store–signed compact JWS and return its payload.
 * Throws AppStoreJWSError on any failure; never returns unverified data.
 */
export async function verifyAppStoreJWS<T = Record<string, unknown>>(
  jws: string,
  options: VerifyOptions = {},
): Promise<T> {
  const rootPin = (options.rootSha256 ?? APPLE_ROOT_CA_G3_SHA256).toLowerCase().replace(/[^0-9a-f]/g, "");
  const now = options.now ?? new Date();

  if (typeof jws !== "string") throw new AppStoreJWSError("JWS must be a string");
  const parts = jws.split(".");
  if (parts.length !== 3) throw new AppStoreJWSError("Not a compact JWS");
  const [h64, p64, s64] = parts;

  let header: { alg?: string; x5c?: string[] };
  try {
    header = JSON.parse(new TextDecoder().decode(base64UrlToBytes(h64)));
  } catch {
    throw new AppStoreJWSError("Bad JWS header");
  }
  if (header.alg !== "ES256") throw new AppStoreJWSError("Unexpected JWS alg");
  if (!Array.isArray(header.x5c) || header.x5c.length !== 3) {
    throw new AppStoreJWSError("Expected a three-certificate x5c chain");
  }

  const certs = header.x5c.map((c) => parseCertificate(base64ToBytes(c)));
  const [leaf, intermediate, root] = certs;

  const rootFingerprint = toHex(await crypto.subtle.digest("SHA-256", ab(root.der)));
  if (rootFingerprint !== rootPin) throw new AppStoreJWSError("Untrusted root certificate");

  if (!contains(leaf.tbs, APPLE_LEAF_MARKER)) throw new AppStoreJWSError("Leaf is not an App Store signing certificate");
  if (!contains(intermediate.tbs, APPLE_INTERMEDIATE_MARKER)) {
    throw new AppStoreJWSError("Intermediate is not an Apple WWDR certificate");
  }

  if (!(await verifyIssuedBy(leaf, intermediate)) || !(await verifyIssuedBy(intermediate, root))) {
    throw new AppStoreJWSError("Certificate chain signature invalid");
  }

  if (leaf.curveOid !== OID_P256) throw new AppStoreJWSError("Leaf key is not P-256");
  const leafKey = await importSpki(leaf);
  const signature = base64UrlToBytes(s64);
  const signingInput = new TextEncoder().encode(`${h64}.${p64}`);
  const ok = signature.length === 64 &&
    await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, leafKey, ab(signature), ab(signingInput));
  if (!ok) throw new AppStoreJWSError("JWS signature invalid");

  let payload: T & { signedDate?: number };
  try {
    payload = JSON.parse(new TextDecoder().decode(base64UrlToBytes(p64)));
  } catch {
    throw new AppStoreJWSError("Bad JWS payload");
  }

  // Certificates must have been valid when Apple signed this (Apple's library
  // does the same when it is not doing online revocation checks). A signedDate
  // in the future is refused so it can't be used to dodge the check.
  const signedAt = typeof payload.signedDate === "number" ? new Date(payload.signedDate) : now;
  if (signedAt.getTime() > now.getTime() + 5 * 60 * 1000) throw new AppStoreJWSError("signedDate is in the future");
  for (const c of [leaf, intermediate, root]) {
    if (signedAt < c.notBefore || signedAt > c.notAfter) {
      throw new AppStoreJWSError("Certificate not valid at signedDate");
    }
  }

  return payload as T;
}

/** Fields of JWSTransactionDecodedPayload this backend uses. */
export interface AppStoreTransaction {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  purchaseDate?: number;
  expiresDate?: number;
  revocationDate?: number;
  isUpgraded?: boolean;
  appAccountToken?: string;
  environment?: string;
  type?: string;
  signedDate?: number;
}

/** Fields of responseBodyV2DecodedPayload this backend uses. */
export interface AppStoreNotification {
  notificationType: string;
  subtype?: string;
  notificationUUID?: string;
  data?: {
    bundleId?: string;
    environment?: string;
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
  signedDate?: number;
}
