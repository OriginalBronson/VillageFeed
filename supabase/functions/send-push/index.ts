// APNs delivery for VillageFeed (plan 04). Fired by database webhooks on:
//   - matches insert            → "🎉 It's a trade!" to both parties
//   - group_messages insert     → message preview to members (not sender)
//   - group_members insert      → "X joined <group>" to existing members
//   - profiles update           → "You're live in Discover" on status → active
//
// Deploy:  supabase functions deploy send-push --no-verify-jwt
//          (webhook calls arrive with the service-role key in the
//           Authorization header; the function verifies it itself)
// Secrets: supabase secrets set APNS_KEY_P8="$(cat AuthKey_XXXX.p8)" \
//            APNS_KEY_ID=XXXXXXXXXX APNS_TEAM_ID=YYYYYYYYYY \
//            APNS_TOPIC=com.bronsongarcia.VillageFeed APNS_ENV=sandbox
//          (APNS_ENV=production for App Store builds)
//
// Quiet by design: only events where a human acted toward you produce a push.
// No like notifications, no digests, no marketing (plan 04 scope).

import { createClient } from "jsr:@supabase/supabase-js@2";

type WebhookPayload = {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  record: Record<string, unknown>;
  old_record?: Record<string, unknown>;
};

// ---------- APNs JWT (ES256, cached ~50 min) ----------

let cachedJWT: { token: string; issuedAt: number } | null = null;

function base64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function apnsJWT(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT && now - cachedJWT.issuedAt < 3000) return cachedJWT.token;

  const p8 = Deno.env.get("APNS_KEY_P8")!;
  const keyID = Deno.env.get("APNS_KEY_ID")!;
  const teamID = Deno.env.get("APNS_TEAM_ID")!;

  const pem = p8.replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "").replace(/\s/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"],
  );

  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyID }));
  const claims = base64url(JSON.stringify({ iss: teamID, iat: now }));
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const token = `${header}.${claims}.${base64url(new Uint8Array(signature))}`;
  cachedJWT = { token, issuedAt: now };
  return token;
}

async function push(token: string, payload: Record<string, unknown>): Promise<number> {
  const host = Deno.env.get("APNS_ENV") === "production"
    ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
  const res = await fetch(`${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${await apnsJWT()}`,
      "apns-topic": Deno.env.get("APNS_TOPIC")!,
      "apns-push-type": "alert",
      "apns-priority": "10",
    },
    body: JSON.stringify(payload),
  });
  return res.status;
}

// ---------- Recipient resolution ----------

Deno.serve(async (req) => {
  const authHeader = req.headers.get("Authorization") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  if (!authHeader.includes(serviceKey)) {
    return new Response(JSON.stringify({ error: "service role required" }), { status: 401 });
  }

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey);
  const payload: WebhookPayload = await req.json();

  // recipient user_id → {title, body, deepLink}
  const notifications: { userID: string; title: string; body: string; link: Record<string, string> }[] = [];

  const nameOf = async (id: string): Promise<string> => {
    const { data } = await admin.from("profiles").select("name").eq("id", id).single();
    return (data?.name as string) || "A neighbor";
  };

  const blockedEitherWay = async (a: string, b: string): Promise<boolean> => {
    const { data } = await admin.from("blocks").select("blocker_id")
      .or(`and(blocker_id.eq.${a},blocked_id.eq.${b}),and(blocker_id.eq.${b},blocked_id.eq.${a})`);
    return (data ?? []).length > 0;
  };

  if (payload.table === "matches" && payload.type === "INSERT") {
    const a = payload.record.a as string, b = payload.record.b as string;
    const [nameA, nameB] = [await nameOf(a), await nameOf(b)];
    notifications.push(
      { userID: a, title: "🎉 It's a trade!", body: `You and ${nameB} both want to trade`, link: { kind: "match" } },
      { userID: b, title: "🎉 It's a trade!", body: `You and ${nameA} both want to trade`, link: { kind: "match" } },
    );
  } else if (payload.table === "group_messages" && payload.type === "INSERT") {
    const senderID = payload.record.sender_id as string;
    const groupID = payload.record.group_id as string;
    const text = payload.record.text as string;
    if (payload.record.is_system) {
      return new Response(JSON.stringify({ skipped: "system message" }));
    }
    const { data: group } = await admin.from("groups").select("name").eq("id", groupID).single();
    const senderName = await nameOf(senderID);
    const { data: members } = await admin.from("group_members")
      .select("member_id,last_read_at").eq("group_id", groupID);
    for (const m of members ?? []) {
      const memberID = m.member_id as string;
      if (memberID === senderID) continue;
      // Respect blocks in both directions (plan 02-§2).
      if (await blockedEitherWay(memberID, senderID)) continue;
      // Suppress for members actively reading this chat (read marker touched
      // in the last minute — plan 07's last_read_at doubles as presence).
      const lastRead = m.last_read_at ? new Date(m.last_read_at as string).getTime() : 0;
      if (Date.now() - lastRead < 60_000) continue;
      notifications.push({
        userID: memberID,
        title: `${senderName} (${group?.name ?? "your group"})`,
        body: text.slice(0, 160),
        link: { kind: "message", group_id: groupID },
      });
    }
  } else if (payload.table === "group_members" && payload.type === "INSERT") {
    const joinerID = payload.record.member_id as string;
    const groupID = payload.record.group_id as string;
    const { data: group } = await admin.from("groups").select("name").eq("id", groupID).single();
    const joinerName = await nameOf(joinerID);
    const { data: members } = await admin.from("group_members")
      .select("member_id").eq("group_id", groupID).neq("member_id", joinerID);
    for (const m of members ?? []) {
      notifications.push({
        userID: m.member_id as string,
        title: "New cook at the table",
        body: `${joinerName} joined ${group?.name ?? "your group"}`,
        link: { kind: "group", group_id: groupID },
      });
    }
  } else if (payload.table === "profiles" && payload.type === "UPDATE") {
    const newStatus = payload.record.status as string;
    const oldStatus = payload.old_record?.status as string | undefined;
    if (newStatus === "active" && oldStatus === "pendingReview") {
      notifications.push({
        userID: payload.record.id as string,
        title: "You're live in Discover",
        body: "Your profile was approved — neighbors can find you now.",
        link: { kind: "approved" },
      });
    }
  }

  // Deliver to every registered device; prune tokens APNs rejects.
  let sent = 0;
  for (const n of notifications) {
    const { data: tokens } = await admin.from("device_tokens")
      .select("token").eq("user_id", n.userID);
    for (const t of tokens ?? []) {
      const status = await push(t.token as string, {
        aps: { alert: { title: n.title, body: n.body }, sound: "default" },
        link: n.link,
      });
      if (status === 200) sent++;
      if (status === 410 || status === 400) {
        await admin.from("device_tokens").delete().eq("token", t.token as string);
      }
    }
  }

  return new Response(JSON.stringify({ notified: notifications.length, delivered: sent }), {
    headers: { "content-type": "application/json" },
  });
});
