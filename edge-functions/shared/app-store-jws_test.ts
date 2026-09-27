import { assertEquals, assertRejects } from "std/assert/mod.ts";
import { AppStoreJWSError, base64UrlToBytes, verifyAppStoreJWS } from "./app-store-jws.ts";
import fixture from "./testdata/app-store-jws-fixture.json" with { type: "json" };

// US-EDGE005. The fixture chain was made with openssl the way Apple's is
// shaped: a P-384 root, a P-384 intermediate carrying Apple's WWDR marker
// extension (1.2.840.113635.100.6.2.1) and a P-256 leaf carrying the App Store
// marker (1.2.840.113635.100.6.11.1). Tests pin the fixture's root; production
// pins Apple Root CA - G3.
const now = new Date(fixture.signedDate + 60_000);
const opts = { rootSha256: fixture.rootSha256, now };

function b64url(s: string): string {
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

Deno.test("a correctly signed transaction verifies and returns its payload", async () => {
  const tx = await verifyAppStoreJWS<{ productId: string; originalTransactionId: string }>(fixture.validTransaction, opts);
  assertEquals(tx.productId, "net.wellvo.family.monthly");
  assertEquals(tx.originalTransactionId, "2000000000");
});

Deno.test("the production pin (Apple Root CA - G3) refuses any other root", async () => {
  await assertRejects(() => verifyAppStoreJWS(fixture.validTransaction, { now }), AppStoreJWSError, "Untrusted root");
});

Deno.test("an edited payload fails the signature", async () => {
  const [h, p, s] = fixture.validTransaction.split(".");
  const payload = JSON.parse(new TextDecoder().decode(base64UrlToBytes(p)));
  payload.productId = "net.wellvo.familyplus.yearly";
  const forged = [h, b64url(JSON.stringify(payload)), s].join(".");
  await assertRejects(() => verifyAppStoreJWS(forged, opts), AppStoreJWSError, "signature");
});

Deno.test("an intermediate without Apple's marker is refused", async () => {
  await assertRejects(() => verifyAppStoreJWS(fixture.noMarkerIntermediate, opts), AppStoreJWSError, "Intermediate");
});

Deno.test("alg other than ES256 and short chains are refused", async () => {
  const [h, p, s] = fixture.validTransaction.split(".");
  const header = JSON.parse(new TextDecoder().decode(base64UrlToBytes(h)));
  const none = [b64url(JSON.stringify({ ...header, alg: "none" })), p, s].join(".");
  await assertRejects(() => verifyAppStoreJWS(none, opts), AppStoreJWSError, "alg");
  const short = [b64url(JSON.stringify({ ...header, x5c: header.x5c.slice(0, 2) })), p, s].join(".");
  await assertRejects(() => verifyAppStoreJWS(short, opts), AppStoreJWSError, "three-certificate");
});

Deno.test("a payload signed 'in the future' is refused", async () => {
  await assertRejects(
    () => verifyAppStoreJWS(fixture.validTransaction, { ...opts, now: new Date(fixture.signedDate - 3_600_000) }),
    AppStoreJWSError,
    "future",
  );
});
