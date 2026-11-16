# Implementation checklist

Source of truth: [`notes/imposter-app-plan.md`](../notes/imposter-app-plan.md). Continue in order and preserve the rules and scoring formulas there.

- [x] 1. Scaffold Expo web/native app and initial responsive landing screen.
- [x] 2. Theme tokens and reusable button, input, and avatar controls; web build passes. Accessibility audit remains.
- [x] 3. Anonymous guest sessions for room actions. Persistent profile editing/statistics remain.
- [ ] 4. Permanent account flow and guest upgrade.
- [x] 5. Initial Supabase schema, membership-scoped reads, guest room create/join, lobby snapshot. Live project setup and integration validation remain.
- [ ] 6. Lobby settings, readiness, and capacity.
- [x] 7. Private roles/word delivery, acknowledgement, and sequential clue RPC.
- [x] 8. Editable suspect ballots and atomic lock.
- [x] 9. Majority extra-clue decision and pass reset.
- [x] 10. Three scoring modes and idempotent result finalization.
- [x] 11. Roulette animation, result ballot breakdown, match title calculation, and host match-finish action.
- [ ] 12. Profile photo, statistics, account deletion, basic heartbeat/reconciliation added; abuse review, blocking, and database-backed verification remain.
- [ ] 13. Web/native release preparation.

## Checkpoint: foundation

- [x] Install dependencies and generate the lockfile.
- [x] Web production export completes successfully. Browser interaction check remains.
- [ ] Confirm React Native app launches on a device/simulator.
- [x] Room actions connect to Supabase and display setup errors if configuration is absent.
