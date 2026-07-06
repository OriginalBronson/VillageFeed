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
  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    return new Response(JSON.stringify({ error: deleteError.message }), { status: 500 });
  }
  // Storage objects aren't FK-cascaded — remove the user's photo folder.
  await admin.storage.from("photos").remove([`${user.id}/profile.jpg`]);

  return new Response(JSON.stringify({ deleted: user.id }), {
    headers: { "content-type": "application/json" },
  });
});
