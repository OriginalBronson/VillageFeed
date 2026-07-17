// Account deletion (App Store requirement 5.1.1(v)): the signed-in user calls
// this with their own JWT; the function verifies it and deletes the auth user.
// Profile, dishes, swipes, messages, etc. cascade via foreign keys.
//
// Deploy:  supabase functions deploy delete-account

import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "missing bearer token" }), { status: 401 });
  }

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error } = await anonClient.auth.getUser();
  if (error || !user) {
    return new Response(JSON.stringify({ error: "invalid token" }), { status: 401 });
  }

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  // Storage objects aren't FK-cascaded — remove the user's entire photo
  // folder (profile photo AND every dish photo; orphaned photos of deleted
  // users are a GDPR problem — plan 02-§5). Storage goes first: if the auth
  // deletion below fails the user can retry, whereas the reverse order can
  // strand photos with no owner able to call this endpoint again.
  const { data: objects } = await admin.storage.from("photos").list(user.id, { limit: 1000 });
  const paths = (objects ?? []).map((o) => `${user.id}/${o.name}`);
  if (paths.length > 0) {
    await admin.storage.from("photos").remove(paths);
  }
  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    return new Response(JSON.stringify({ error: deleteError.message }), { status: 500 });
  }

  return new Response(JSON.stringify({ deleted: user.id }), {
    headers: { "content-type": "application/json" },
  });
});
