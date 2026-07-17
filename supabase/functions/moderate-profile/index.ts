// Server-side profile moderation: triages pending review_cases with the
// Claude API and auto-resolves clear approvals. Reject/escalate verdicts stay
// queued for a human moderator (resolve via SQL editor or future dashboard).
//
// Deploy:  supabase functions deploy moderate-profile
// Secrets: supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
// Invoke:  POST with { "case_id": "<uuid>" }, or {} to triage the whole queue.
// Auth:    requires the service role key (never expose to the app); intended
//          to be called from a scheduled job or the dashboard, not clients.

import { createClient } from "jsr:@supabase/supabase-js@2";

const MODEL = "claude-haiku-4-5"; // cheap classification tier — moderation cost control

const SYSTEM = `You are the trust & safety reviewer for VillageFeed, a neighborhood app where \
people trade portions of home-cooked meals. Review the profile and return a verdict:
- "approve": ordinary profile about food and meal trading, nothing unsafe.
- "reject": clear violation — sexual content, harassment, hate, selling non-food goods or \
services, soliciting money, contact-info harvesting, content dangerous to food safety, or \
prohibited foods (raw milk, home-canned low-acid goods, wild-harvested mushrooms, raw or \
undercooked meat preparations, alcohol — Terms of Service §5).
- "escalate": ambiguous, or a report alleging real-world harm that a human should judge.
Reported profiles are already frozen, so a wrong "approve" unfreezes them — be conservative.`;

Deno.serve(async (req) => {
  const authHeader = req.headers.get("Authorization") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  if (!authHeader.includes(serviceKey)) {
    return new Response(JSON.stringify({ error: "service role required" }), { status: 401 });
  }

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey);
  const { case_id } = await req.json().catch(() => ({}));

  let query = supabase.from("review_cases").select("*").eq("resolved", false);
  if (case_id) query = query.eq("id", case_id);
  const { data: cases, error } = await query.limit(20);
  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });

  const results = [];
  for (const c of cases ?? []) {
    const { data: profile } = await supabase
      .from("profiles").select("name, neighborhood, bio, dietary_tags").eq("id", c.subject_id).single();
    const { data: dishes } = await supabase
      .from("dishes").select("name, blurb, allergen_note").eq("owner_id", c.subject_id);

    const summary = `Name: ${profile?.name}. Neighborhood: ${profile?.neighborhood}. ` +
      `Bio: ${profile?.bio}. Dishes: ${(dishes ?? []).map(d => `${d.name}: ${d.blurb} (${d.allergen_note})`).join("; ")}`;
    const trigger = c.trigger_kind === "report"
      ? `This profile was reported by another user for: ${c.trigger_detail}.`
      : "This is a newly submitted profile awaiting first review.";

    const apiResponse = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 300,
        system: SYSTEM,
        output_config: {
          format: {
            type: "json_schema",
            schema: {
              type: "object",
              properties: {
                verdict: { type: "string", enum: ["approve", "reject", "escalate"] },
                rationale: { type: "string" },
              },
              required: ["verdict", "rationale"],
              additionalProperties: false,
            },
          },
        },
        messages: [{ role: "user", content: `${trigger}\n\nProfile:\n${summary}` }],
      }),
    });

    if (!apiResponse.ok) {
      results.push({ case: c.id, error: await apiResponse.text() });
      continue;
    }

    const message = await apiResponse.json();
    const text = message.content?.find((b: { type: string }) => b.type === "text")?.text;
    let verdict = "escalate";
    let rationale = "unparseable model output";
    try {
      const parsed = JSON.parse(text);
      verdict = parsed.verdict;
      rationale = parsed.rationale;
    } catch (_) { /* keep escalate */ }

    const autoResolve = verdict === "approve";
    await supabase.from("review_cases").update({
      ai_verdict: verdict,
      ai_rationale: rationale,
      resolved: autoResolve,
      resolved_by: autoResolve ? "ai" : null,
    }).eq("id", c.id);

    if (autoResolve) {
      await supabase.from("profiles").update({ status: "active" }).eq("id", c.subject_id);
    }
    results.push({ case: c.id, verdict });
  }

  return new Response(JSON.stringify({ triaged: results }), {
    headers: { "content-type": "application/json" },
  });
});
