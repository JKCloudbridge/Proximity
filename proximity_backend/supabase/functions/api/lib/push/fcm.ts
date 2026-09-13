// Sprint 11 -- the real FCM (Android) + APNs (iOS) send path. Both
// platforms go through ONE call here: Firebase's HTTP v1 API delivers to
// Android directly and relays to APNs on Apple's behalf once an APNs Auth
// Key is uploaded to the Firebase project console (SPRINT_PLANNING.md
// §3.2's own prerequisite) -- there is no separate direct-APNs code path in
// this backend, the `apns` field on the v1 message payload below is how an
// iOS-specific override (if any were ever needed) would be expressed, not a
// second send mechanism.
//
// Checked live before writing any of this, per this project's standing
// third-party-API rule (the same one Sprint 8's razorpay.ts header states
// and cites sources for):
//   - Send endpoint: POST https://fcm.googleapis.com/v1/projects/{projectId}/messages:send
//     (firebase.google.com/docs/cloud-messaging/send/v1-api; also
//     firebase.google.com/docs/reference/fcm/rest). Body: {"message": {...}}.
//   - Auth: a Google OAuth2 access token via the JWT-bearer grant
//     (RFC 7523) against https://oauth2.googleapis.com/token, grant_type
//     `urn:ietf:params:oauth:grant-type:jwt-bearer`, scope
//     `https://www.googleapis.com/auth/firebase.messaging`, signed RS256
//     with the service account's own private key. Same "fetch + Web Crypto
//     instead of the full SDK" call Sprint 8 made for Razorpay (lib/
//     payments/razorpay.ts's own header) -- Node's `google-auth-library`
//     has no Deno-native equivalent worth pulling in for one JWT signature
//     and one token exchange; this is directly expressible with Deno's
//     built-in `fetch`/Web Crypto, same audit-surface reasoning.
//   - An invalid/unregistered token comes back from the send call as an
//     error with `error.status` (or, on some responses, `error.details[]`'s
//     own `errorCode`) of `UNREGISTERED` or `INVALID_ARGUMENT` -- see
//     `isUnregisteredTokenError` below, used by lib/push/index.ts to clear
//     a stale users.fcm_token rather than retry it forever.
//
// **Never executed against a real Firebase project** -- same standing
// caveat every third-party integration in this project carries until real
// credentials exist (Sprint 8's Razorpay adapter is the precedent for
// exactly this shape of gap). No FCM_SERVICE_ACCOUNT_JSON secret is set in
// any .env.example in this repo -- getFcmConfig() throws
// FcmNotConfiguredError the moment anything tries to send without it,
// mirroring getPaymentGateway()'s own PaymentGatewayNotConfiguredError
// (lib/payments/index.ts).

export class FcmNotConfiguredError extends Error {
  constructor() {
    super("FCM_SERVICE_ACCOUNT_JSON is not set -- no real Firebase project is configured yet");
    this.name = "FcmNotConfiguredError";
  }
}

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

function getServiceAccount(): ServiceAccount {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
  if (!raw) throw new FcmNotConfiguredError();
  // Parsed fresh on every call rather than cached at module-load time --
  // this module has no top-level await, and a bad/missing secret should
  // surface as a clear, catchable error at send time, not a cryptic
  // cold-start failure before any route even runs.
  const parsed = JSON.parse(raw);
  if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
    throw new FcmNotConfiguredError();
  }
  return parsed as ServiceAccount;
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlEncodeString(value: string): string {
  return base64UrlEncode(new TextEncoder().encode(value));
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return crypto.subtle.importKey("pkcs8", bytes, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
}

// Cached per Edge Function instance (a token is valid 1 hour; Supabase
// Edge Functions can serve several requests on one warm instance before a
// cold start recycles it, same "don't re-do an expensive round trip every
// single call" reasoning any OAuth2 client library would apply internally
// -- there's just no library here to do it for us).
let cachedToken: { accessToken: string; expiresAtMs: number } | null = null;

async function getAccessToken(account: ServiceAccount): Promise<string> {
  const now = Date.now();
  if (cachedToken && cachedToken.expiresAtMs - 60_000 > now) {
    return cachedToken.accessToken;
  }

  const issuedAt = Math.floor(now / 1000);
  const expiresAt = issuedAt + 3600;
  const header = base64UrlEncodeString(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64UrlEncodeString(
    JSON.stringify({
      iss: account.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      exp: expiresAt,
      iat: issuedAt,
    }),
  );
  const unsigned = `${header}.${claims}`;

  const key = await importPrivateKey(account.private_key);
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  const jwt = `${unsigned}.${base64UrlEncode(new Uint8Array(signature))}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!response.ok) {
    throw new Error(`FCM OAuth2 token exchange failed: ${response.status} ${await response.text()}`);
  }

  const body = (await response.json()) as { access_token: string; expires_in: number };
  cachedToken = { accessToken: body.access_token, expiresAtMs: now + body.expires_in * 1000 };
  return cachedToken.accessToken;
}

export type PushMessage = {
  title: string;
  body: string;
  /** Arbitrary string-valued data payload -- deep-link routing info lives here, read by the app's own notification-tap handler, never in `notification` (the OS renders that half, the app never parses it). */
  data?: Record<string, string>;
};

export type SendPushResult =
  | { ok: true; messageId: string }
  | { ok: false; errorCode: string; unregistered: boolean };

/**
 * Send one push to one FCM registration token. Never throws for an
 * ordinary delivery failure (a stale/unregistered token, a malformed
 * token) -- those are expected, common outcomes a caller needs to branch
 * on (lib/push/index.ts clears `users.fcm_token` on `unregistered: true`),
 * not exceptional ones. Only throws for real configuration/transport
 * failures (no service account configured, the token endpoint itself
 * unreachable) -- same "expected outcome vs. genuine failure" split
 * lib/payments/razorpay.ts's own verify functions already draw.
 */
export async function sendPush(token: string, message: PushMessage): Promise<SendPushResult> {
  const account = getServiceAccount();
  const accessToken = await getAccessToken(account);

  const response = await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        token,
        notification: { title: message.title, body: message.body },
        data: message.data ?? {},
        // High priority on both platforms -- a recurring-list reminder or a
        // rider assignment ping is time-sensitive (§11/§8.5); FCM's own
        // default priority ('normal' on Android) can be delayed behind
        // battery-optimization batching, which defeats "fires ... at the
        // right time" for the reminder case specifically.
        android: { priority: "high" },
        apns: { headers: { "apns-priority": "10" } },
      },
    }),
  });

  if (response.ok) {
    const result = (await response.json()) as { name: string };
    return { ok: true, messageId: result.name };
  }

  const errorBody = await response.json().catch(() => null) as
    | { error?: { status?: string; details?: Array<{ errorCode?: string }> } }
    | null;
  const errorCode =
    errorBody?.error?.details?.find((d) => d.errorCode)?.errorCode ?? errorBody?.error?.status ?? `HTTP_${response.status}`;

  return { ok: false, errorCode, unregistered: isUnregisteredTokenError(response.status, errorCode) };
}

function isUnregisteredTokenError(httpStatus: number, errorCode: string): boolean {
  return httpStatus === 404 || errorCode === "UNREGISTERED" || errorCode === "INVALID_ARGUMENT";
}
