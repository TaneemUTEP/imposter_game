# Codebase Guide

This guide explains how to read and change the source code. It focuses on implementation responsibilities and data flow; for the product rules and change history, see [imposter-app-plan.md](imposter-app-plan.md), [implementation-outline.md](implementation-outline.md), and [changes-made.md](changes-made.md).

## 1. Project layers

```text
App.js / src/screens
    UI state, user input, and phase-specific rendering
             |
src/lib/supabase.js
    Auth, persistence, and RPC wrappers
             |
supabase/migrations
    PostgreSQL schema, RLS, transactions, game rules, and stored results
```

The client is not the source of truth for game state. A screen reads a server snapshot, renders it, and requests an action through a Supabase RPC. The database validates whether that action is permitted and performs all authoritative transitions. Realtime and polling refresh the UI from the database.

The app uses conditional rendering in `App.js` rather than a navigation library: it shows the landing/account view, the profile/account view, or one active `RoomScreen`.

## 2. Entry and screen ownership

### `App.js`

- `App` installs `ThemeProvider` around the app tree.
- `AppContent` owns only app-level routing and the locally remembered player name.
- `createRoom` and `joinRoom` validate simple form requirements, call `src/lib/supabase.js`, and put the returned room identity into state.
- `useAccountName` receives the profile screen's callback and updates the local display name.
- Do not move round state or score calculation here. Those belong in the room screen and database.

### `src/screens/RoomScreen.js`

This is the main multiplayer UI. Its server phase determines which interaction is enabled:

| Database phase | UI responsibility |
|---|---|
| No round / `aborted` | Lobby, room settings, seated roster, waitlist, readiness, host start action. |
| `roles` | Show only the caller's private role card and acknowledge button. |
| `clues` | Show the shared clue list, calculate the next visible seat from the random starter and submitted clue count, and allow that player's clue submission. |
| `voting` | Restore the caller's ballot once per new round, let them edit suspect selections, and display vote participation without targets. |
| `continue_vote` | Show/edit the caller's More clues/Reveal choice and display participation count. |
| `reveal` | Animate the presentation carousel and list imposters as server reveal timestamps make them public. |
| `results` | Show word/hint, roles, ballots, correct picks, caught/escaped details, round points, match totals, and host controls. |

#### RoomScreen state

- `snapshot`: authorized `get_room_snapshot` response. It contains the room roster and public round information, not secret role assignments.
- `me`: current Supabase user ID used to identify host/member UI state.
- `secret`: caller-only response from `get_private_round`; never copy this into shared client state or a broadcast.
- `clue`: temporary clue input. It is cleared after successful submission.
- `selected`: the current caller's local suspect selection. On the first refresh for a new round it initializes from `round.my_vote`.
- `matchTitles`: display cache populated by the finish-match response or snapshot.
- `rouletteIndex`: presentation-only carousel index. It does not determine roles or scoring.
- `loadedVoteRound`: prevents polling from overwriting an in-progress local ballot edit with the last saved ballot.
- `busy` / `error`: shared action feedback state, handled by `act`.

#### RoomScreen synchronization

- `refresh` fetches the public snapshot, asks the server to advance an expired continuation/reveal when needed, fetches the caller's private role, and records the current user ID.
- The private `room:<uuid>` channel listens for changes to room, roster, round, and waitlist rows. The database authorizes a room member or waitlisted user for that topic.
- Polling runs every five seconds normally and every second during a continuation deadline or reveal. Foregrounding the app forces a refresh.
- `maintainRoom` runs on a heartbeat to update presence and reconcile a stale host or abandoned in-progress round.
- `act(operation)` wraps button mutations: it clears prior errors, sets busy state, calls the RPC, refreshes after success, displays a useful error on failure, and always clears busy state.

When changing this component, preserve the separation between **snapshot data** (safe for the whole room), **private role data** (one player only), and **local drafts** (unsaved input). The render uses one large phase switch expressed as JSX conditionals; add phase-specific behavior in the matching condition and verify it cannot appear during another phase.

### `src/screens/ProfileScreen.js`

- `loadProfile` reads the current auth session, the caller's profile/stat RPC, and a signed URL for a private avatar.
- `submitAccount` creates an email account or signs in, then returns the chosen display name to `AppContent`.
- `saveGuestAccount` calls Supabase Auth `updateUser` so the guest identity can be secured without switching identities.
- `saveName` calls the profile-owner RPC.
- `choosePhoto` requests device permission, crops/resizes/compresses an image, enforces the upload size limit, uploads it under the current user's storage path, and saves that path.
- `deleteAccount` confirms before calling the deletion RPC. Its database cascades and historical-data retention still need isolated verification; do not assume the UI's anonymization wording proves that behavior.
- `Metric` and `createStyles` are presentation helpers.

## 3. Reusable UI and theme

| File | Contract |
|---|---|
| `src/components/ActionButton.js` | Accessible themed action button; accepts `label`, optional `color`, `onPress`, `secondary`, and `disabled`. |
| `src/components/TextField.js` | Theme-aware wrapper around React Native `TextInput`; accepts a required accessibility label and forwards other native props. |
| `src/components/Avatar.js` | Emoji/color fallback avatar. It does not itself fetch profile photos. |
| `src/components/ThemeToggle.js` | Accessible light/dark toggle backed by theme context. |
| `src/theme/ThemeContext.js` | Owns theme state, restores it from AsyncStorage, and exposes `mode`, `palette`, and `toggleTheme`. |
| `src/theme/palette.js` | Base color palette plus shared spacing and radius tokens. Dark-mode colors are defined in `ThemeContext.js`. |

Add new visual tokens to the theme rather than embedding repeated colors in screens. Keep accessibility roles/labels on custom controls.

## 4. Client libraries and contracts

### `src/lib/supabase.js`

This module creates one client using `EXPO_PUBLIC_SUPABASE_URL` and `EXPO_PUBLIC_SUPABASE_ANON_KEY`; it exports `null` if either value is missing. It stores the auth session in AsyncStorage. It should only use the public anon key.

Exported functions are thin, named wrappers around backend operations:

- Auth: `createEmailAccount`, `signInWithEmail`, `ensureGuestSession`.
- Rooms: `createRoom`, `joinRoom`, `roomSnapshot`, `setReady`, `updateRoomSettings`, `leaveRoom`.
- Rounds: `startRound`, `privateRound`, `acknowledgeRole`, `submitClue`, `submitBallot`, `chooseContinuation`, `advanceContinuation`, `advanceReveal`.
- Match/presence: `finishMatch`, `maintainRoom`.

Wrappers throw Supabase errors so screens can display them. Keep business validation in PostgreSQL too; client checks are for quick feedback, not security.

`createRoom` persists a command UUID until success. If a request commits remotely but its response is lost, another tap reuses the UUID so the database can return the already-created room.

The RPCs `submitClue`, `submitBallot`, and `chooseContinuation` still pass a `version` argument for the established function contract. The latest ballot/continuation database implementation serializes by locking the round row and validates the current phase/deadline; it does not use the client version as its final lock condition.

### `src/lib/gameRules.js`

Pure CommonJS reference scorer used by `tests/unit/gameRules.test.js`. It validates fixture rosters and ballots, counts only civilian hits against imposters, and returns half-point units. It is not called by the live room screen and must not replace database finalization.

### `server/contracts/game.js`

Reference game-contract helpers (room size, clue validation, point reference, continuation majority). The current app does not import this module. Its clue normalization is simpler than the SQL validator, so database validation remains authoritative. If this file is wired into a runtime later, reconcile the differences and add tests first.

### `src/lib/authErrors.js`

Maps known Supabase error codes/messages into user-facing setup and sign-in guidance. Add mappings here rather than duplicating auth-specific error text in screens.

## 5. Server data model and RPC responsibilities

Core tables (created/extended by migrations):

| Table | Purpose |
|---|---|
| `profiles` | Display name, optional avatar object path, and profile identity. |
| `rooms`, `room_members`, `room_waitlist` | Room code, host/settings/status, seated players, queued players, and readiness. |
| `matches`, `rounds` | Match-level frozen configuration and per-round phase/version/deadlines. |
| `round_roles`, `round_secrets` | Role/name/seat snapshots and private word/hint. Client table reads are intentionally restricted. |
| `clues`, `ballots`, `continuation_votes`, `role_acknowledgements` | Round actions and votes. Ballot targets are private until results. |
| `round_results`, `achievements` | Persisted points and match titles. |
| `word_pairs` | Backend-selected word/hint pool. |
| `game_rate_limits` | Per-user create/join request buckets. |

Public client actions call security-definer RPCs with a blank `search_path`, explicit grants, and server-side checks. The main flow is:

```text
create_room / join_room
  -> get_room_snapshot
  -> set_ready / update_room_settings
  -> start_round
  -> get_private_round / acknowledge_role
  -> submit_clue (sequential, per pass)
  -> submit_ballot (editable until all ballots lock)
  -> choose_more_clues / advance_continuation
  -> advance_reveal / finalize_round
  -> get_room_snapshot(results)
  -> start_round again or finish_match
```

Key server-side guarantees:

- `start_round` locks the room, seats ready waitlisted users between rounds, snapshots the match configuration and roster, assigns roles, and chooses a word not yet used in that match when the selected pool still has unused words.
- `submit_clue` checks participant, phase, turn order, one-word length/link/secret constraints, and advances the phase only after every role has submitted.
- `submit_ballot` locks the round row. The phase changes to `continue_vote` only after every participant has a valid ballot; no later ballot edit can cross that phase boundary.
- `choose_more_clues` allows each participant to revise their choice until the deadline. `advance_continuation` decides by strict majority and is retry-safe.
- `advance_reveal`/`finalize_round` enforce the shared reveal duration and write results once.
- `finish_match` checks host and phase, computes titles, marks the match finished, and returns the room to a lobby for a new match.
- `get_room_snapshot` includes public roster/clue/voter-progress data. Before results it excludes other players' ballots, roles, and the secret word.

## 6. Migrations and SQL reading order

Read migrations in ascending order; later files replace earlier RPC definitions. The final behavior is the result of the entire sequence, not the first definition of a function.

- `0001`–`0008`: schema, room/round commands, clues, votes, scoring, lobby, snapshots, and early fixups.
- `0009`–`0012`: membership security helper, profiles/storage/titles/deletion, and presence/cleanup.
- `0013`–`0016`: room-code alphabet/randomness, host continuity, and seat-allocation corrections.
- `0017`–`0022`: frozen match config, roster snapshots, waitlist/category flow, scoring/reveal correction, retry-safe voting, private Realtime, and waitlist/host leave cleanup.

Important SQL implementation points:

- `0018_gameplay_flow.sql` owns the current `start_round`, `submit_clue`, `join_room`, `set_ready`, and scoring/reveal definitions.
- `0020_retry_safe_voting.sql` is the final definition of `submit_ballot`, `choose_more_clues`, and `advance_continuation`.
- `0019_snapshot_and_match_results.sql` is the final definition of `get_room_snapshot` and `finish_match`.
- `0022_waitlist_leave_cleanup.sql` is the final definition of `leave_room` and `get_private_round`.
- `0021_private_room_realtime.sql` authorizes private room topics and adds room-state tables to the Realtime publication.

Production has migrations through `0022` applied. SQL integration tests must run against a disposable local Supabase instance or isolated staging project, never against production.

## 7. Tests, tooling, and configuration

- `tests/unit/gameRules.test.js`: Node's built-in test runner; no external test framework is needed for the pure scorer.
- `tests/integration/gameplay_invariants.test.sql`: pgTAP checks for migration/schema/seed invariants; not yet run in an isolated environment.
- `eslint.config.mjs`: ESLint flat config; excludes generated/dependency directories and enables the recommended JavaScript rules with browser/Node globals.
- `tsconfig.json`: currently accepts JavaScript files but has `checkJs: false`; a successful `npm run typecheck` does not provide strict type checking of the JavaScript app.
- `app.json`, `babel.config.js`, `eas.json`, `vercel.json`: Expo app identity/build configuration, Babel preset, EAS build profiles, and Vercel web export configuration.
- `supabase/config.toml`: local Supabase settings, including anonymous sign-in; this does not itself change the hosted production Auth settings.
- `.env.example`: names the public Supabase client variables. `.env` is ignored; never copy its values into documentation.

## 8. Known gaps and cautions for future changes

- The room screen is a large component with phase-specific JSX. Before extracting subcomponents, preserve the three data boundaries: public snapshot, caller-private role, and local unsubmitted input.
- Automatic cleanup is not a background job. `reconcile_room` runs when a connected room client calls `maintainRoom`; simply closing the app can leave stale membership rows.
- An active round is aborted when a seated player explicitly leaves. Revisit only with a product decision about how to handle incomplete clue/vote turns.
- `server/contracts/game.js` and the live SQL validator are not identical. Do not treat the reference helper as a security boundary.
- Account deletion/anonymization needs dedicated database tests against real foreign-key behavior.
- Email password-reset UI, comprehensive E2E multiplayer automation, real-device native verification, and store release preparation remain unfinished.
