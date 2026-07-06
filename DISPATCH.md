# DISPATCH.md — browser tasks for Claude dispatch

Instructions to complete in Google Chrome. Work top to bottom; each section says
what to record at the end. Record all outputs in a single summary at the end so
Bronson can paste them into the project.

## 1. Create the Supabase project

1. Go to https://supabase.com/dashboard and sign in (Bronson's account — reuse the
   org that hosts the existing "SpaceEngine/GetSpaced" project).
2. Click **New project**. Name: `villagefeed`. Generate (and record) a strong
   database password. Region: closest US region. Free tier is fine.
3. Wait for provisioning to finish.
4. Go to **Project Settings → Data API** and record:
   - **Project URL** (looks like `https://<ref>.supabase.co`)
   - **anon/public key**

## 2. Run the schema migration

1. In the project, open **SQL Editor → New query**.
2. Open the raw file
   https://github.com/OriginalBronson/VillageFeed/blob/main/supabase/migrations/0001_init.sql
   (if the repo is private, sign into GitHub first), copy the entire contents,
   paste into the SQL editor, and click **Run**.
3. Confirm it reports success. If any statement fails, record the exact error
   text and stop this section (don't retry with modifications).

## 3. Google Cloud OAuth client (for "Continue with Google")

1. Go to https://console.cloud.google.com/ and sign in with the same Google
   account.
2. Create a new project named `VillageFeed` (or reuse an existing personal one).
3. Navigate to **APIs & Services → OAuth consent screen**:
   - User type: **External**. App name: `VillageFeed`. Add Bronson's email as
     support + developer contact. Scopes: just the default (email, profile,
     openid). Add Bronson's email as a test user. Save.
4. Navigate to **APIs & Services → Credentials → Create credentials →
   OAuth client ID**:
   - Application type: **Web application** (yes, web — Supabase brokers the
     OAuth flow, the iOS app opens it in a browser sheet).
   - Name: `villagefeed-supabase`.
   - Authorized redirect URI: `https://<ref>.supabase.co/auth/v1/callback`
     (substitute the project ref from step 1.4).
   - Create, and record the **Client ID** and **Client secret**.

## 4. Enable the Google provider in Supabase

1. Back in the Supabase dashboard: **Authentication → Sign In / Providers → Google**.
2. Toggle it on, paste the Client ID and Client secret from step 3.
3. In **Authentication → URL Configuration**, add `villagefeed://auth-callback`
   to the **Redirect URLs** list. Save.

## 5. Anthropic API key for server-side moderation

1. Go to https://console.anthropic.com/ and sign in.
2. Create a new API key named `villagefeed-moderation` in the default workspace.
   Record the key (starts `sk-ant-`).
3. In the Supabase dashboard, go to **Edge Functions → Secrets** (or Project
   Settings → Edge Functions) and add a secret: name `ANTHROPIC_API_KEY`,
   value = the key just created.

## 6. Final summary to report back

Produce one block containing:
- Supabase Project URL and anon key  → to paste into `VillageFeed/SupabaseConfig.swift`
- Database password (label clearly)
- Google OAuth Client ID (secret stays only in Supabase — do not echo it)
- Confirmation that: migration ran clean, Google provider is enabled,
  redirect URL added, ANTHROPIC_API_KEY secret set.

## Not yet (future dispatch runs)

- Deploy the `moderate-profile` edge function (needs the Supabase CLI, not a
  browser — Bronson runs `supabase functions deploy moderate-profile` locally).
- App Store Connect app record + TestFlight (blocked on Apple Developer
  Program membership).
