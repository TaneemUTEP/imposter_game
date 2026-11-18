# Imposter App — Implementation Outline

Current map of the implemented product, code, database, and remaining work. This describes the repository and verified release state as of **2026-11-17**. The original product specification remains in [imposter-app-plan.md](imposter-app-plan.md); this file records implementation details and known gaps.

## 1. Product at a glance

Imposter is a private-room, word-based social deduction game for the web and Expo native targets. Players use a six-character room code, receive private roles, give clues in turn, vote on suspected imposters, decide whether to request another clue pass, and see a timed reveal with scoring.

The application uses Expo, React Native, and React Native Web. Supabase supplies authentication, PostgreSQL, storage, and Realtime. PostgreSQL functions are authoritative for room membership, game phases, ballots, scoring, and results.

## 2. Implemented player experience

### Entry and accounts

- A player may enter a display name and create a room or join by code without first creating an email account; guest access uses Supabase anonymous authentication.
- The display name is saved locally for convenience and is also written to the server profile when the player creates or joins.
- Account options support email account creation and sign-in. The profile screen supports upgrading a guest identity with email/password, signing out, and requesting account deletion.
- Profile editing includes display name, private avatar upload, basic round/imposter statistics, and earned titles.
- Profile photo selection crops to a square, resizes to at most 512 pixels, converts to JPEG, enforces a 5 MB upload limit, stores it in a private bucket, and loads it with a signed URL.
- Theme selection is available in the main, room, and profile views.

### Rooms and lobby

- Rooms support four to eight seated players and use six-character codes from an unambiguous allowed alphabet.
- The host can choose Team, Partial, or Deception scoring; choose one or two imposters where the room size permits; and select one or more of six word categories.
- Players ready themselves before a round. Settings are locked while a match is active and are copied into the match record.
- A room has a maximum capacity of eight across its seated roster and waitlist. A person who joins during an active round gets a queue position and can mark ready for the next round.
- At the next round start, queued players are assigned open seats. The host can start only after the seated players and promoted queued players are ready.
- Room creation supports a client command ID for retry behavior. The database records rate-limit counters for create/join operations per authenticated user.

### Round flow

1. The host starts a round. The server snapshots player names/seats and match settings, picks a random starting player, assigns one or two imposters, and selects a word/hint.
2. Civilians receive the secret word. Imposters receive a hint but not the word. Each player acknowledges their role card before clues begin.
3. Each player submits one clue in stable seat order, beginning with the random starter. A clue is one word, up to 30 characters, and cannot be a link or the normalized secret word. A submitted clue cannot be edited.
4. Each player selects exactly the configured number of suspects and can edit their ballot until the final ballot changes the round phase. Imposters vote too. The UI shows who has voted without revealing other players' selections.
5. A shared 15-second continuation decision opens. Players may change More clues/Reveal until the deadline. Missing choices count as Reveal. More clue passes preserve roles and word, clear ballots, and select a new starter.
6. The reveal animates for four seconds plus 1.5 seconds for each additional imposter. Imposters are exposed in stable seat order; the word, complete results, and ballots become available at the reveal's end.
7. The backend stores each round result once. The host may start another round or finish the match. On match finish, the app calculates titles from scored results.

## 3. Scoring rules in the database

Catch counts use **civilian ballots only**. An imposter is caught only if strictly more than half of all civilians selected that imposter; a tie means the imposter escaped. Let `K` be the number of imposters, `C` the number of civilians, `correct(v)` the actual imposters selected by a civilian, and `fooled(i) = C - hits(i)`.

- **Team:** Civilians receive one point only when every imposter is caught. Each escaping imposter receives one point.
- **Partial:** Civilians receive `correct(v) / K`; each escaping imposter receives one point.
- **Deception:** Civilians receive `correct(v) / K`; each escaping imposter receives one point per civilian fooled.
- Scores are stored as integer half-point units. Caught imposters receive zero.

The client-side reference implementation in `src/lib/gameRules.js` exists for tests and presentation logic. PostgreSQL finalization remains authoritative.

## 4. Results and titles

- Results include the secret word and hint, player roles, each player's suspects, correct civilian picks, round points, cumulative match points, and caught/escaped details for imposters.
- The UI shows whether an imposter escaped and how many civilians they fooled, or how many civilian votes caught them.
- Match titles include Sharp Eye, Wild Guesser, Master of Disguise, Caught in the Act, Invisible Imposter, and Perfect Read, subject to the thresholds in the product specification.
- The backend stores round results once and uses role name/seat snapshots so results do not depend on current profile names or room membership.

## 5. Code map

| Path | Responsibility |
|---|---|
| `App.js` | Landing page, saved guest name, account/profile entry, and room-screen routing. |
| `src/screens/RoomScreen.js` | Lobby, settings, ready state, role card, clue turn, voting, continuation, reveal, results, and match controls. |
| `src/screens/ProfileScreen.js` | Guest/account flows, profile editing, avatar upload, statistics, sign-out, and account deletion request. |
| `src/lib/supabase.js` | Supabase client and RPC wrappers for auth, rooms, rounds, votes, maintenance, and profiles. |
| `src/lib/gameRules.js` | Pure reference scorer used by unit tests; not the production scoring authority. |
| `src/components/` | Shared buttons, text fields, avatar, and theme control. |
| `src/theme/` | Color palettes and theme context. |
| `supabase/migrations/` | PostgreSQL schema, RLS policies, RPCs, seeds, and Realtime setup. |
| `tests/unit/gameRules.test.js` | Scoring rule tests using Node's built-in test runner. |
| `tests/integration/gameplay_invariants.test.sql` | pgTAP checks for schema and word-pool invariants. |
| `notes/imposter-app-plan.md` | Original user-approved product plan and rules. |
| `notes/changes-made.md` | Chronological change log and template for future entries. |

## 6. Database migration map

All migrations through `0022` are recorded as applied to the linked production Supabase project.

| Migration | Main responsibility |
|---|---|
| `0001_game_schema.sql` | Profiles, rooms, members, matches, rounds, private roles/secrets, clues, ballots, results, base RLS. |
| `0002_room_commands.sql` | Room create/join RPCs. |
| `0003_round_commands.sql` | Round start, private role retrieval, sequential clue submission. |
| `0004_voting_and_words.sql` | Word-pair table/seeds, ballots, continuation votes. |
| `0005_finalize_round.sql` | Server-side score calculation and result storage. |
| `0006_lobby_and_role_ack.sql` | Readiness, lobby settings, role acknowledgement, snapshot/start-round functions. |
| `0007_snapshot_and_fixups.sql` | Room snapshot and reveal progression updates. |
| `0008_clue_order_and_result_reveal.sql` | Clue ordering and reveal-related corrections. |
| `0009_rls_membership_helper.sql` | Membership-scoped helper and policy corrections. |
| `0010_profiles_statistics_and_storage.sql` | Profile statistics, profile changes, and private avatar storage. |
| `0011_match_titles_and_deletion.sql` | Match finish/title calculation and account deletion RPC. |
| `0012_presence_and_cleanup.sql` | Room heartbeat, host reconciliation, leave behavior, and continuation deadline advancement. |
| `0013_fix_room_code_randomness.sql` | Corrected secure random-byte function qualification. |
| `0014_use_valid_room_code_alphabet.sql` | Made generated room codes satisfy the database's code constraint. |
| `0015_prevent_null_room_hosts.sql` | Prevented null host assignment and closed empty rooms on explicit leave. |
| `0016_fix_room_seat_selection.sql` | Corrected selection of open seats during room joins. |
| `0017_gameplay_foundation.sql` | Added category/match configuration, round/role snapshots, waitlist/rate tables, word normalization and constraints, and hardened membership helpers. |
| `0018_gameplay_flow.sql` | Added create retry IDs, category settings, waitlist promotion/readiness, round creation, clue validation, civilian-only scoring, reveal timing, and expanded word seeds. |
| `0019_snapshot_and_match_results.sql` | Added waitlist-aware authorized snapshots, locked-down result details, match totals/titles, and return to lobby after match finish. |
| `0020_retry_safe_voting.sql` | Made ballot edits phase-locked and continuation choices editable until deadline; made deadline advancement idempotent. |
| `0021_private_room_realtime.sql` | Added private room channel policies and Realtime publication for room-state tables. |
| `0022_waitlist_leave_cleanup.sql` | Added waitlist removal, safe host transfer when leaving, and time-aware private role data. |

## 7. Security and data boundaries

- Supabase Auth supplies identities; guests use anonymous auth. The app bundle uses only the public anon key. Never put a service-role key in client code or an `EXPO_PUBLIC_*` variable.
- Room/round commands run through PostgreSQL RPCs. Server-side checks cover membership, host permissions, turn order, clue content, ballot size/self-votes, phase transitions, and scoring.
- RLS restricts room and player data. Round roles and secrets do not have client table-read policies; `get_private_round` returns only the caller's role-appropriate information.
- Ballots remain private until results. The pre-reveal snapshot exposes vote participation, not other players' target choices.
- Realtime channels are private and use a room-membership or waitlist authorization check. Polling and app-foreground refresh remain as synchronization fallbacks.
- Avatar storage is private and served using short-lived signed URLs.

## 8. Leaving, closing, and retained data

- Tapping **Leave room** removes the caller from the room or waitlist. If the host leaves, the server transfers host to a seated member or, if needed, a queued player.
- If a player leaves during an unfinished round, that active round is aborted. Completed round results are retained when players leave.
- When the final seated player explicitly leaves, the room status becomes `closed`; future joins reject the code. Room/match/result rows are not automatically purged by this path.
- Closing the app is not equivalent to leaving. The client heartbeat stops; reconciliation can mark a member disconnected, transfer a stale host after 60 seconds, or abort an unfinished round after 120 seconds. There is no scheduled background cleanup that removes every disconnected member or closes every abandoned room.
- Do not describe account deletion as verified anonymization: the UI and RPC exist, but account-deletion effects on all historical foreign-key records need isolated database testing and review.

## 9. Commands and verification status

| Command/check | Current status |
|---|---|
| `npm run web` | Starts the Expo web development server. |
| `npm run build:web` | Passed on the gameplay implementation before the ESLint-only change. |
| `npm run lint` | Passes with ESLint 10 flat config. |
| `npm run typecheck` | Exits successfully, but the project is JavaScript and `checkJs` is disabled; this is not strict JavaScript type checking. |
| `npm run test:unit` | Six tests pass for the reference scoring rules. |
| `npm run test:integration` | Not run: this requires an isolated local Supabase database. |
| `npm run test:e2e` | Script is present, but Playwright/eight-session test coverage is not installed or verified. |
| Native iOS/Android run/build | Expo configuration exists; real-device and store-build verification remains. |

Database tests must target a local Supabase stack or a dedicated staging project with disposable test data. Do not run database reset or destructive integration tests against the production project.

## 10. Remaining work

- Create/use an isolated Supabase test target (local Docker or separate staging project), then run migration/integration tests against it.
- Add and run multi-client browser tests, including eight players, concurrent join/vote changes, reconnect, waitlist promotion, and all scoring modes.
- Perform a real browser UI/runtime check and iOS/Android device checks.
- Verify account deletion and anonymization behavior against actual foreign-key/cascade rules; implement password reset if required by product scope.
- Finish the release checklist: app icons/splash and permissions, EAS development/preview builds, privacy/terms/support, store metadata, and submission requirements.
- Reconcile older documentation/checklists that still say migrations are pending, the word pool is only a starter set, or ESLint is unavailable.
