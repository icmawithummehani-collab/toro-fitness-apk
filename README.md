# Toro Fitness — Flutter + Supabase

Android/iOS app (same method as the Ahmed Gym starter). Business (owner_admin) and Member roles.
**Not compiled or tested yet** — run `flutter analyze` and fix any small issues for your Flutter version.

## Setup
1. `flutter create --org pk.torofitness toro_fitness`, then copy this package's `lib/` and `pubspec.yaml` over it. `flutter pub get`.
2. Create a Supabase project. Run `supabase/schema.sql` in SQL Editor.
3. Auth: enable Email (and Phone if members log in by phone).
4. Create the owner login: Supabase Dashboard > Authentication > Add user, copy its UUID, then run:
   `insert into public.profiles(id,role,full_name) values ('<UUID>','owner_admin','Toro Owner');`
5. Deploy the Edge Function: `supabase functions deploy admin-create-member`
6. Run: `flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLIC_ANON_KEY`

Never put the service-role key in the app.

## Rules (enforced in the database, not just the UI)
- Payments: only the business can write. Members can only view their own.
- Plans: only the business assigns members to plans and edits prices.
- Freeze / resume / cancel: business or the member (own plan only) via `set_subscription_status`. Resuming extends the end date by the frozen days.
- Check-in: member calls `generate_checkin_code` (new 6-digit code each time, 10 min, single use); admin enters it in `mark_attendance`.
- Dashboard: `admin_dashboard(period)` returns all the numbers; live check-ins use Supabase Realtime.

## Assumed fees (PKR, edit in app > Plans)
Monthly 6,000 · Quarterly 16,000 · Yearly 55,000 · Day Pass 1,000

## Install on a phone (no Flutter on your computer needed)
1. Create a free GitHub account and a new **private** repository. Upload everything in this folder (keep `.github/workflows/build-apk.yml`).
2. Repo > Settings > Secrets and variables > Actions > add two secrets: `SUPABASE_URL` and `SUPABASE_ANON_KEY` (the public anon key, never the service-role key).
3. Repo > Actions > "Build Toro Fitness APK" > Run workflow. After ~5-10 min download `toro-fitness-apk` (contains `app-release.apk`).
4. Send the APK to the Android phone (WhatsApp/Drive/USB), open it, allow "Install unknown apps" when asked. The Toro Fitness icon appears on the home screen.

Notes: this APK is signed with a debug key, fine for installing directly on your gym's and members' phones. For Google Play you need your own release keystore. iPhone builds need a Mac and an Apple Developer account (TestFlight); the same code works for iOS.
