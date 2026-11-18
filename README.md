# Imposter

A word based social deduction game for web, iOS, and Android. The product rules and complete build plan are in [`notes/imposter-app-plan.md`](notes/imposter-app-plan.md).

## Current status

The app includes guest room creation/joining, lobby controls, private role delivery, clue and vote rounds, three scoring modes, result reveal, profiles, and Supabase migrations. Live online use requires the Supabase migrations to be applied.

## Code documentation

- [`notes/codebase-guide.md`](notes/codebase-guide.md) explains the source files, client/server boundaries, room and round flow, database functions, migrations, and current implementation caveats.
- [`notes/implementation-outline.md`](notes/implementation-outline.md) describes the product and planned behavior.
- [`notes/changes-made.md`](notes/changes-made.md) records the implementation changes made so far.

## Start

```sh
npm install
npm run web
```

For native device development, run `npm start` and open the project with Expo Go or a development build. Copy `.env.example` to `.env` and supply the Supabase project URL and public anon key. Never put a service role key in the app.

## Supabase setup

Install the Supabase CLI, link this project to your Supabase project, and apply the migrations in `supabase/migrations` with `supabase db push`. For guest room creation on the hosted project, enable **Allow anonymous sign-ins** under Supabase **Authentication → Sign In / Providers**. For local Supabase development, `supabase/config.toml` enables anonymous sign-ins. Email accounts are also available from the app's Account options. The migrations create private avatar storage and server functions for room/game commands. After applying them, set `EXPO_PUBLIC_SUPABASE_URL` and `EXPO_PUBLIC_SUPABASE_ANON_KEY` in `.env` and restart Expo.

The current round word-pair seed is a small starter set. Replace/expand it with the planned curated 150 word/hint pairs before public release. Run migrations and game commands against a dedicated development project first.

## Vercel

Vercel builds the static web app with `npm run build:web` into `dist/` (`vercel.json`). Add `EXPO_PUBLIC_SUPABASE_URL` and `EXPO_PUBLIC_SUPABASE_ANON_KEY` to the Vercel project's Production and Preview environment variables, then redeploy. These public client values are embedded in the web bundle; never configure a Supabase service-role key as an `EXPO_PUBLIC_*` variable.
