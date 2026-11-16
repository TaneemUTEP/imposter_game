# Imposter

A word based social deduction game for web, iOS, and Android. The product rules and complete build plan are in [`notes/imposter-app-plan.md`](notes/imposter-app-plan.md).

## Current status

The app includes guest room creation/joining, lobby controls, private role delivery, clue and vote rounds, three scoring modes, result reveal, profiles, and Supabase migrations. Live online use needs a Supabase project.

## Start

```sh
npm install
npm run web
```

For native device development, run `npm start` and open the project with Expo Go or a development build. Copy `.env.example` to `.env` and supply the Supabase project URL and public anon key. Never put a service role key in the app.

## Supabase setup

Install the Supabase CLI, link this project to your Supabase project, and apply the migrations in `supabase/migrations` with `supabase db push`. Enable anonymous sign-ins and email confirmation in the Supabase Auth settings. The migrations create private avatar storage and server functions for room/game commands. After applying them, set `EXPO_PUBLIC_SUPABASE_URL` and `EXPO_PUBLIC_SUPABASE_ANON_KEY` in `.env` and restart Expo.

The current round word-pair seed is a small starter set. Replace/expand it with the planned curated 150 word/hint pairs before public release. Run migrations and game commands against a dedicated development project first.
