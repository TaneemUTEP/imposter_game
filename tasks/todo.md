# Implementation checklist

Source of truth: [`notes/imposter-app-plan.md`](../notes/imposter-app-plan.md). Continue in order and preserve the rules and scoring formulas there.

- [x] 1. Scaffold Expo web/native app and initial responsive landing screen.
- [x] 2. Theme tokens and reusable button, input, and avatar controls; web build passes. Accessibility audit remains.
- [x] 3. Anonymous guest sessions for room actions. Persistent profile editing/statistics remain.
- [ ] 4. Permanent account flow and guest upgrade.
- [x] 5. Initial Supabase schema, membership-scoped reads, guest room create/join, lobby snapshot. Live project setup and integration validation remain.
- [x] 6. Lobby settings, readiness, category selection, waitlist capacity, and between-round promotion (migration 0018; production apply pending).
- [x] 7. Private roles/word delivery, acknowledgement, stable seat/name snapshots, and sequential clue validation (migrations 0017–0018; production apply pending).
- [x] 8. Editable suspect ballots, voter progress, and phase-locked final ballot (migration 0020; production apply pending).
- [x] 9. Editable majority extra-clue choices through the shared deadline and idempotent pass/reveal transition (migration 0020; production apply pending).
- [x] 10. Three scoring modes, civilian-only catch counts, match configuration snapshots, and idempotent result finalization (migrations 0017–0019; production apply pending).
- [x] 11. Timed sequential imposter reveal, full result breakdown, match totals, Perfect Read title, and host match-finish action (migrations 0018–0019; production apply pending).
- [ ] 12. Profile photo, statistics, account deletion, basic heartbeat/reconciliation added; abuse review, blocking, and database-backed verification remain.
- [ ] 13. Web/native release preparation.

## Checkpoint: foundation

- [x] Install dependencies and generate the lockfile.
- [x] Web production export completes successfully. Browser interaction check remains.
- [ ] Confirm React Native app launches on a device/simulator.
- [x] Room actions connect to Supabase and display setup errors if configuration is absent.

## Gameplay engine checkpoint (2026-11-16)

- [x] Added 120 original word/hint pairs (150+ total), six-category selection, answer-hiding hints, and no-repeat-per-match selection.
- [x] Added retry-safe room creation IDs and per-user database create/join rate limits.
- [x] Added an 8-seat waitlist with readiness, next-round promotion, private member channels, and safe waitlist departure/host handoff.
- [x] Added result snapshots that survive player departures and never reveal ballots before results.
- [x] Added 6 scoring reference unit tests; `npm run test:unit` passes.
- [x] `npm run build:web` passes; `npm run typecheck` exits successfully (JavaScript checking is disabled because the app sources are JavaScript).
- [ ] `npm run lint` is unavailable because ESLint is not installed in the current dependency set.
- [ ] SQL integration suite is authored but not run: no isolated local Supabase database/Docker target is available. Do not run it against production.
- [ ] Apply migrations 0017–0022 to the linked Supabase project only after reviewing the prepared migrations and confirming the production change.
- [ ] Real-browser multiplayer/eight-session verification, mobile-device verification, permanent account/profile completion, and store release work remain.
