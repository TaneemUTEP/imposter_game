# Changes Made

Chronological record of shipped changes. Add a dated entry here after each meaningful implementation, migration, or deployment. For the current feature map and behavioral details, see [implementation-outline.md](implementation-outline.md).

## Current release snapshot — 2026-11-17

- Git branch: `main`
- Latest commit: `9449e06 chore: install eslint and configure linting`
- Production Supabase migrations: `0001` through `0022` are applied.
- Gameplay implementation commit: `988ee9c feat: complete authoritative imposter gameplay flow`
- ESLint is installed and `npm run lint` passes.
- Six scoring-rule unit tests pass. Web export passed before the ESLint-only commit. SQL integration tests have not been run because there is no isolated local database/Docker target.
- A Vercel check reported success for the gameplay implementation commit; the deployment status for the later ESLint-only commit was not rechecked.

## Change history

### Foundation and hosting

- `b025e93` — Built the Expo app foundation: responsive landing page, shared theme/components, room and profile screens, Supabase client setup, and initial application structure.
- `05a2da4` — Prepared the web build for hosting and improved room controls.
- `87ac4a4` — Set a valid Vercel framework preset.
- `7504783` — Added Supabase CLI support for database migrations.
- `66f7064` — Aligned Expo modules with Expo SDK 54.
- `ee418be` — Improved account setup and added the dark theme.

### Room and database reliability fixes

- `c8e37f4` — Qualified the database room-code random-byte function.
- `3c4bc60` — Restricted generated join codes to the room table's allowed alphabet.
- `5b080fe` — Prevented host handoff from assigning a null host and added empty-room closing behavior.
- `f201c0b` — Fixed seat selection so joins use an available seat.

### Gameplay engine — commit `988ee9c` and migrations `0017`–`0022`

- Added room category configuration and immutable match snapshots for scoring mode, imposter count, and selected categories.
- Added stable player name/seat snapshots for each round, plus an eight-seat waitlist for arrivals during active rounds.
- Added readiness for queued players and promotion into seats between rounds.
- Added 120 new word/hint pairs, bringing the seeded pool to 150 or more across six categories. Added normalized answer checks and match-level no-repeat selection until the selected pool is exhausted.
- Added retry IDs for room creation and per-user database rate-limit accounting for room creation and joining.
- Tightened clue checks for one-word input, length, links, and exact normalized secret-word matches.
- Changed voting to serialize on the round and lock on phase, so vote edits do not fail just because the client version counter changed. Continuation choices stay editable through the shared 15-second deadline.
- Corrected scoring so only civilian ballots determine whether imposters are caught and how many civilians they fooled. Finalization is idempotent and waits for the reveal duration.
- Added sequential imposter reveal timing, saved result snapshots, correct-pick breakdowns, round points, match totals, and the `Perfect Read` title.
- Added private room Realtime policies and publication entries for room state. The client also refreshes on app foreground and polls as a fallback.
- Updated the room screen with category controls, queue/readiness status, voter progress, result details, next-round controls, and match-finish titles.
- Added six unit tests for scoring boundaries, both imposter counts, and invalid ballots; added a pgTAP database invariant test file.
- Applied and verified production migrations `0017`–`0022` after explicit user approval.

### Linting — commit `9449e06`

- Installed `eslint`, `@eslint/js`, and `globals` as development dependencies and updated `package-lock.json`.
- Added `eslint.config.mjs` for the repository's JavaScript and JSX sources, excluding generated output and dependencies.
- `npm run lint` now passes.

## Ongoing entry template

Copy this section when recording the next change:

```markdown
### YYYY-MM-DD — Short change title

- Changed:
- Why:
- Files/migrations:
- Verification:
- Deployment or migration status:
```
