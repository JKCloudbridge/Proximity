// Sprint 8 -- HMAC-SHA256 helpers shared by every gateway adapter that needs
// one (razorpay.ts today; a real PayU adapter would reuse this too, same
// "one shared helper, not one per adapter" precedent as slots.ts's
// istDateString). Uses the Web Crypto API (`crypto.subtle`), available as a
// global in the Deno Edge Function runtime with no import needed -- no npm
// dependency for something this small and security-sensitive; fewer moving
// parts to audit.

const encoder = new TextEncoder();

async function importHmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

function toHex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** HMAC-SHA256(message, secret) as a lowercase hex digest. */
export async function hmacSha256Hex(message: string, secret: string): Promise<string> {
  const key = await importHmacKey(secret);
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(message));
  return toHex(signature);
}

/**
 * Constant-time-ish string comparison. Razorpay's own docs don't mandate
 * this (a plain `===` would "work"), but a signature check is exactly the
 * kind of comparison where a naive early-exit string compare has a real,
 * well-known timing side channel -- cheap to close, worth closing.
 */
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}
