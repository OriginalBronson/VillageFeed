// Entitlement sync: the app posts its StoreKit 2 signed transaction (JWS) and
// this function verifies it against Apple's certificate chain before flipping
// profiles.is_plus — the flag that gates the who_liked_me() identities RPC.
// Clients cannot write is_plus themselves (column privileges, migration 0005),
// so this is the only self-serve path into the paid tier.
//
// Deploy:  supabase functions deploy sync-entitlement
// Invoke:  POST { "jws": "<Transaction.jwsRepresentation>" } with the user's
//          JWT. Omitting jws (or null) reports "no active subscription" and
//          drops the paid tier.
//
// Xcode StoreKit-configuration purchases are signed by a local test authority,
// not Apple, so they are rejected here by design — the simulator path is the
// DEBUG-only "unlock Plus" toggle in the paywall sheet.
//
// ponytail: App Store Server Notifications (refunds, billing-retry lapses)
// should eventually drive this server-to-server. Until then the server learns
// of changes when a client next checks in, and plus_expires_at (migration
// 0006) caps how long a lapsed subscription can linger.

import { createClient } from "jsr:@supabase/supabase-js@2";
import * as x509 from "npm:@peculiar/x509@1";

const BUNDLE_ID = "com.bronsongarcia.VillageFeed";
const PRODUCT_ID = "app.villagefeed.plus.monthly";
// Apple Root CA - G3 — the root of every App Store transaction chain.
// SHA-256 fingerprint from https://www.apple.com/certificateauthority/
const APPLE_ROOT_CA_G3_SHA256 =
  "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";

function base64urlToBytes(s: string): Uint8Array {
  const b64 = s.replaceAll("-", "+").replaceAll("_", "/")
    .padEnd(Math.ceil(s.length / 4) * 4, "=");
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

async function sha256Hex(data: ArrayBuffer): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Verifies the x5c chain (leaf ← intermediate ← pinned Apple root, all within
// their validity windows) and the ES256 signature, then returns the decoded
// transaction payload. Throws with a reason on any failure.
async function verifyTransactionJWS(jws: string): Promise<Record<string, unknown>> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("malformed JWS");
  const header = JSON.parse(new TextDecoder().decode(base64urlToBytes(parts[0])));
  if (header.alg !== "ES256" || !Array.isArray(header.x5c) || header.x5c.length < 3) {
    throw new Error("unexpected JWS header");
  }
  const [leaf, intermediate, root] = header.x5c.map(
    (der: string) => new x509.X509Certificate(der),
  );
  if (await sha256Hex(root.rawData) !== APPLE_ROOT_CA_G3_SHA256) {
    throw new Error("chain does not terminate at Apple Root CA - G3");
  }
  const now = new Date();
  if (!(await intermediate.verify({ publicKey: root, date: now })) ||
      !(await leaf.verify({ publicKey: intermediate, date: now }))) {
    throw new Error("certificate chain verification failed");
  }
  const key = await leaf.publicKey.export(
    { name: "ECDSA", namedCurve: "P-256" },
    ["verify"],
  );
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    base64urlToBytes(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!valid) throw new Error("JWS signature invalid");
  return JSON.parse(new TextDecoder().decode(base64urlToBytes(parts[1])));
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

Deno.serve(async (req) => {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "missing bearer token" }, 401);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error } = await anonClient.auth.getUser();
  if (error || !user) return json({ error: "invalid token" }, 401);

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const setPlus = (is_plus: boolean, plus_expires_at: string | null) =>
    admin.from("profiles").update({ is_plus, plus_expires_at }).eq("id", user.id);

  const { jws } = await req.json().catch(() => ({}));
  if (!jws) {
    // The client reports no active subscription (lapsed or never bought).
    const { error: clearError } = await setPlus(false, null);
    if (clearError) return json({ error: clearError.message }, 500);
    return json({ plus: false });
  }

  let tx: Record<string, unknown>;
  try {
    tx = await verifyTransactionJWS(jws);
  } catch (e) {
    return json({ error: `transaction rejected: ${(e as Error).message}` }, 403);
  }

  if (tx.bundleId !== BUNDLE_ID || tx.productId !== PRODUCT_ID ||
      tx.revocationDate !== undefined) {
    return json({ error: "transaction is not an active Plus subscription" }, 403);
  }
  // appAccountToken ties the purchase to the Supabase account that made it —
  // without this check any subscriber's JWS could be replayed to unlock Plus
  // on an unrelated account.
  if (typeof tx.appAccountToken !== "string" ||
      tx.appAccountToken.toLowerCase() !== user.id.toLowerCase()) {
    return json({ error: "transaction does not belong to this account" }, 403);
  }

  const expiresMs = typeof tx.expiresDate === "number" ? tx.expiresDate : 0;
  if (expiresMs <= Date.now()) {
    const { error: clearError } = await setPlus(false, null);
    if (clearError) return json({ error: clearError.message }, 500);
    return json({ plus: false });
  }

  const expiresAt = new Date(expiresMs).toISOString();
  const { error: grantError } = await setPlus(true, expiresAt);
  if (grantError) return json({ error: grantError.message }, 500);
  return json({ plus: true, expires_at: expiresAt });
});
