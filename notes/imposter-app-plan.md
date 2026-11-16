# Imposter: complete build plan for ChatGPT 6 Luna

## 1. Product and confirmed game rules

Build a multiplayer secret-word party game for **web, iOS, and Android**, using one shared application codebase.

Players join private rooms using a unique code. The app manages private roles, sequential clue submissions, editable suspect votes, additional clue passes, animated reveals, scoring, profiles, and statistics.

Published versions use private secret words, one-word clues given in turn, and voting. Hints for imposters are an existing variation. Use these as gameplay references, while creating original branding, screens, wording, and assets: [Imposter.app](https://imposter.app/) and [The Imposter App](https://theimposterapp.com/).

### Terminology

Use these terms consistently throughout the UI, code, and documentation:

- **Room:** A private group of players.
- **Match:** A room’s scoring session, containing multiple rounds.
- **Round:** One secret word, one assignment of roles, and one eventual scored result.
- **Clue pass:** Every player submits one clue in sequence. Additional passes preserve the round’s word and roles.

### Room rules

- Support **4–8 players**, including the host.
- Allow one imposter with four players.
- Allow one or two imposters with five to eight players.
- Default to one imposter.
- Display the configured imposter count to everyone.
- Imposters see a hint, but never the secret word before results.
- Imposters do not know who the other imposter is.
- The host chooses the scoring mode and word categories before the match.
- Freeze those settings during the match.
- Players can join only between rounds; joining an active round shows a waiting screen.
- An additional player cannot reserve a ninth room seat.

### Round flow

1. The host starts a round.
2. The backend selects the word, assigns roles randomly, and chooses a random starting player.
3. Each player privately opens their role card.
4. Starting from the selected player, everyone submits one clue in the room’s stable seating order.
5. Everyone selects exactly as many suspects as there are imposters.
6. Players can change submitted votes until the final required vote arrives.
7. The backend atomically locks all suspect votes.
8. A **15-second “More clues or reveal?” decision** opens.
9. If more than half of all round participants choose more clues, start another clue pass.
10. Otherwise, run the roulette reveal and show results.
11. Award points once and update statistics.
12. The host starts the next round or ends the match.

An extra clue pass:

- Preserves roles, secret word, hint, seating order, and previous clues.
- Chooses a fresh random starting player.
- Clears previous suspect votes.
- Awards no points and changes no statistics.
- Has no arbitrary pass limit in the first release.

The first submitted clue begins only after everyone acknowledges their role card. There is no default clue or suspect-vote timer.

### Clues and suspect votes

- Each player gets one clue submission per pass.
- Clues become visible to everyone immediately after submission.
- Accept one word, allowing internal hyphens or apostrophes; reject spaces, links, empty input, and input longer than 30 characters.
- Reject a clue that exactly matches the secret word after normalization. Show a generic rejection message.
- Submitted clues cannot be edited.
- Players cannot vote for themselves.
- Imposters submit suspect votes too, preserving the bluff.
- Only civilian votes determine whether an imposter was caught and how many civilians they fooled.
- Before reveal, show who has voted but hide every other player’s selections.
- Additional-clue choices remain editable until the 15-second deadline. Missing choices count as “reveal.”

## 2. Scoring, results, titles, and profiles

### Exact scoring rules

For a round:

- `C` = number of civilians.
- `K` = number of imposters.
- `hits(i)` = number of civilians who selected imposter `i`.
- Imposter `i` is **caught** when `hits(i) > C / 2`.
- Otherwise, that imposter **escapes**.
- A tie favors the imposter because the civilians did not form a strict majority.
- `correct(v)` = number of actual imposters selected by civilian `v`.
- `fooled(i) = C - hits(i)`.

| Mode | Civilian points | Imposter points |
|---|---|---|
| **Team** | Each civilian receives 1 only if every imposter is caught | Each escaping imposter receives 1; caught imposters receive 0 |
| **Partial** | Each civilian receives `correct(v) / K` | Each escaping imposter receives 1; caught imposters receive 0 |
| **Deception** | Each civilian receives `correct(v) / K` | Each escaping imposter receives `fooled(i)`; caught imposters receive 0 |

With the selected two-imposter maximum, scores use increments of 0.5. Store points as integer half-point units to avoid floating-point errors.

**Required example:** Eight players, two imposters, six civilians. Four civilians select imposter A; two select imposter B.

- A is caught; B escapes.
- Team: B gets 1; A and civilians get 0.
- Partial: civilians get 0, 0.5, or 1 according to their selections; B gets 1.
- Deception: civilians get the same partial credit; B gets 4 because four civilians missed B.

Do not add a separate “imposter guesses the word” victory condition in version one.

### Roulette and results

The roulette is a suspense animation. It does not choose the winner or change scoring.

- The backend finalizes the result and records a shared reveal time before animation begins.
- Animate player avatars in a roughly four-second carousel.
- Reveal multiple imposters sequentially in stable seating order.
- Use server timestamps so all devices reach the same result.
- Keep other roles, the word, and ballots inaccessible until the relevant reveal time.
- Reconnecting players resume the current animation position or go directly to results.
- Reduced-motion mode replaces spinning with a brief transition.

Results show:

- Secret word and hint.
- All imposters.
- Each player’s final suspect selections and correct-pick count.
- Round points and match totals.
- For each imposter: civilians fooled, civilians who caught them, and caught/escaped outcome.
- Personal messages such as “You fooled the majority,” “Some players caught you,” or “Every civilian caught you.”

### Match titles

Titles are playful achievements based on the current match. They do not award points.

| Title | Rule |
|---|---|
| **Sharp Eye** | Highest correct-selection rate among civilians with at least three civilian rounds |
| **Wild Guesser** | Lowest correct-selection rate under the same eligibility rule |
| **Master of Disguise** | Highest escape rate among imposters with at least two imposter rounds |
| **Caught in the Act** | Lowest escape rate under the same eligibility rule |
| **Perfect Read** | Correctly selects every imposter in a round |
| **Invisible Imposter** | Escapes without receiving any civilian selections |

Use correct selections divided by available imposter selections for civilian accuracy. Share titles on ties. Do not award “Wild Guesser” when the lowest eligible accuracy is 100%, or “Caught in the Act” when the lowest eligible escape rate is 100%.

Show titles on the scoreboard and final match summary. Let players hide negative titles in their own interface.

### Profiles and statistics

Support guest access plus optional permanent accounts.

- Guests choose a display name and default avatar.
- Use Supabase anonymous authentication to give guests a real authenticated identity.
- Offer email/password registration, email verification, login, password reset, and logout.
- Upgrade a guest to a new permanent account while retaining the same identity and statistics.
- Signing into an existing account loads that account’s statistics. Do not silently merge identities.
- Offer account switching or linking only outside an active room.
- Explain that unlinked guest access can be lost when local session data is cleared.

Supabase supports anonymous identities and later identity linking; use its documented flow rather than inventing a local guest account system. [Supabase anonymous sign-ins](https://supabase.com/docs/guides/auth/auth-anonymous)

Profiles include:

- Display name and optional uploaded photo.
- Completed rounds and matches.
- Civilian rounds and correct-selection accuracy.
- Perfect civilian ballots.
- Imposter rounds, escapes, and escape rate.
- Total civilians fooled.
- Points separated by scoring mode.
- Earned positive achievements.

Only completed, scored rounds affect statistics. Show “Not enough games” when a percentage has no denominator.

Photos must be resized, stripped of metadata, and validated by actual file content. Accept JPEG, PNG, or WebP up to 5 MB; store a normalized image at most 512 × 512 pixels.

## 3. Architecture, folder structure, and interfaces

### Technology choices

- **Application:** Expo, React Native, React Native Web.
- **Language:** TypeScript inside `src/`; keep root `App.js` as a small entry wrapper matching the screenshot.
- **Navigation:** React Navigation.
- **Backend:** Supabase PostgreSQL, Auth, Storage, Realtime, and Edge Functions.
- **Authority:** PostgreSQL functions handle room membership, turns, votes, phase transitions, scoring, and statistics in transactions.
- **Local state:** React state and context for session, room subscriptions, and temporary form input.
- **Validation:** Zod for client/server request validation, plus database constraints.
- **Builds:** Expo EAS development, preview, and production profiles.
- **Tests:** Jest/React Native Testing Library, database integration tests, and Playwright web tests.

Select the current stable Expo release at implementation time and install compatible native packages through `npx expo install`. Commit the lockfile and record tool versions in the README.

Expo’s cloud builds produce iOS and Android binaries and support managed signing, which allows iOS build preparation from Windows. [Expo build documentation](https://docs.expo.dev/build/introduction/)

### Required folder layout

```text
Imposter/
├── .agents/
├── .expo/                    # Generated; ignored
├── .supabase-home/           # Optional local CLI state; ignored
├── assets/
│   ├── fonts/
│   ├── icons/
│   └── images/
├── dist/                     # Generated web output; ignored
├── node_modules/             # Generated; ignored
├── notes/
│   ├── product-spec.md
│   ├── game-rules.md
│   ├── architecture.md
│   └── release-checklist.md
├── server/
│   ├── contracts/            # Request/response schemas and shared types
│   ├── scripts/              # Administrative and validation tools
│   └── README.md
├── src/
│   ├── components/
│   ├── features/
│   │   ├── auth/
│   │   ├── profiles/
│   │   ├── rooms/
│   │   └── game/
│   ├── hooks/
│   ├── lib/
│   ├── navigation/
│   ├── screens/
│   ├── theme/
│   └── types/
├── supabase/
│   ├── functions/
│   ├── migrations/
│   ├── config.toml
│   └── seed.sql
├── tasks/
│   ├── plan.md
│   └── todo.md
├── tests/
│   ├── unit/
│   ├── integration/
│   └── e2e/
├── .env
├── .env.example
├── .gitignore
├── App.js
├── app.json
├── babel.config.js
├── eas.json
├── package.json
├── package-lock.json
├── tsconfig.json
├── README.md
└── skills-lock.json          # Only if the skill tooling generates it
```

`server/` holds contracts and administrative tools; deployed backend functions live under `supabase/`. Do not add an always-running Node server merely to populate the folder.

### Data model and privacy boundaries

Create migrations for:

- **Profiles:** User identity, display name, avatar path, preferences.
- **Rooms and memberships:** Code, host, seats, connection status, room lifecycle.
- **Matches:** Scoring mode, configuration, status.
- **Rounds and participants:** Immutable participant roster, phase, seating order, starting player, version, timing.
- **Private word content and role assignments:** Secret word, hint, and private player roles.
- **Clue passes and submissions.**
- **Private suspect ballots and continuation choices.**
- **Final results and score entries.**
- **Statistics, achievements, and content reports.**

Keep secret-word content and complete role assignments outside client-readable tables.

Provide separate response types for:

- `RoomSnapshot`: Public room state, participants, clues, turn, submission indicators, deadlines, version.
- `PrivateRoundView`: The caller’s own role, word or hint, and own ballot.
- `RoundResult`: Revealed roles, word, ballots, outcomes, and points.
- `PlayerStats`: Server-derived counters and percentages.
- `GameCommand`: Command identifier, target round/pass, expected version, and validated payload.

Do not fetch all roles and hide them in the UI. The backend must never deliver unauthorized secrets.

### Backend command surface

Implement authenticated operations for:

- Create/join/leave room and reconnect.
- Update lobby settings and readiness.
- Start match and start round.
- Acknowledge role.
- Submit clue.
- Submit or replace suspect vote.
- Submit or replace continuation choice.
- Advance an expired phase.
- Read public state, private state, and authorized results.
- End match.
- Update profile, manage avatar, and delete account.

Use Supabase RPC for transactional game commands. Use Edge Functions for privileged account, storage, and moderation operations.

Every game command must validate membership, phase, participant status, payload, and version. Return stable errors such as `ROOM_FULL`, `VOTING_LOCKED`, `NOT_YOUR_TURN`, and `STALE_STATE`.

Use unique command IDs and database constraints to make retries safe. The last vote and any concurrent vote replacement must serialize on the round record; reject changes processed after the lock.

### Synchronization and security

- Use six-character, uppercase, cryptographically generated room codes, excluding ambiguous characters.
- Enforce code uniqueness among open rooms and retry collisions.
- Rate-limit room creation, joining, authentication, and uploads.
- Enforce capacity inside a transaction.
- Authorize every database read and private Realtime subscription.
- Broadcast public state/version changes; clients refetch their authorized snapshots.
- Treat Realtime and presence as notifications, not authoritative game state.
- Fetch fresh state after reconnection, foregrounding, or a missed-version event.
- Never place service-role credentials in application code or `EXPO_PUBLIC_*` variables.
- Disable public access to room Realtime channels and apply membership policies. [Supabase Realtime authorization](https://supabase.com/docs/guides/realtime/authorization)
- Do not log words, roles, ballots, tokens, or uploaded photo contents.

Clients request deadline advancement when timers expire or on reconnection. The database checks server time and transitions once. A scheduled cleanup handles inactive rooms; gameplay correctness must not depend on a client’s clock.

### Disconnects and abandoned games

- Keep the round roster fixed.
- Preserve a disconnected player’s seat and private assignment for reconnection.
- A disconnected player does not silently become an abstention.
- Transfer host duties to the earliest-joined connected member after a 60-second host absence.
- If a participant leaves permanently, or a required player remains disconnected for 120 seconds, abort the unfinished round without scoring.
- Return remaining players to the between-round lobby.
- Preserve previous completed-round scores.
- Require at least four players to start again.
- Close rooms after 24 hours without activity.

## 4. Screens and implementation sequence

### User experience

Use a **bright, playful visual style**: warm light backgrounds, colorful player cards, bold readable labels, rounded controls, and expressive avatars. Show role and vote meaning with text and icons as well as color.

Build:

- Welcome screen with create/join actions.
- Guest name entry and account screens.
- Profile editing and statistics.
- Room lobby with code, invite link, roster, readiness, and host settings.
- Private role card.
- Sequential clue board with previous passes and active-player indicator.
- Suspect selection and submitted-vote confirmation.
- “More clues or reveal?” decision.
- Roulette reveal.
- Personal result and match scoreboard.
- Final match summary.
- Help, settings, privacy, reporting, blocking, and account deletion.

Support phone layouts first, then tablet and desktop widths. Include keyboard operation on web, accessible labels, large touch targets, screen-reader announcements, reduced motion, and safe-area handling.

### Ordered build tasks for Luna

Work sequentially. Each task must leave a working, verifiable slice. Split tasks further when they require unrelated changes or more than roughly five authored files.

| Step | Deliverable | Acceptance and verification |
|---|---|---|
| 1 | Project scaffold and navigation | Web and native development builds open; type checking and linting pass |
| 2 | Theme and reusable controls | Buttons, inputs, cards, avatars, dialogs, and screen layouts work with keyboard and screen reader |
| 3 | Guest session and profile | A returning guest retains identity; another session cannot edit their profile |
| 4 | Permanent account flow | Verification, login, reset, and guest upgrade work without losing the upgraded guest’s stats |
| 5 | Room creation and joining | Four clients share a lobby; concurrent joins cannot exceed eight seats |
| 6 | Match settings and readiness | Only the host changes valid settings; starting requires every participant to be ready |
| 7 | Secure role assignment | Each client sees only its own permitted role information |
| 8 | Sequential clue pass | Only the active player submits; all clients receive the same ordered clues |
| 9 | Suspect voting | Correct selection count enforced; vote changes work until atomic locking |
| 10 | Additional clue decision | Strict majority starts another pass with the same roles and a random starter |
| 11 | Scoring and finalization | All three formulas pass exact examples; retries never duplicate awards |
| 12 | Roulette and results | All clients reveal the same saved result; reduced motion and reconnect work |
| 13 | Match progression and titles | Next rounds retain scores; final summaries and title eligibility are correct |
| 14 | Photos and persistent statistics | Valid photos upload safely; completed rounds update the correct counters |
| 15 | Disconnect and abuse handling | Host transfer, round abort, reporting, blocking, and account deletion work |
| 16 | Release preparation | Production web build and native preview builds pass the full acceptance suite |

Seed at least **150 original word/hint pairs across six categories**. Keep the source data private to the backend. Validate missing hints, duplicate normalized words, and hints that contain the answer. Avoid repeating a word during a match until its eligible pool is exhausted.

Create these npm scripts:

```text
npm run start
npm run web
npm run lint
npm run typecheck
npm run test:unit
npm run test:integration
npm run test:e2e
npm run build:web
npm run check
```

Document local Supabase startup/reset commands separately. Database resets must target local or explicitly designated test projects.

### Luna working instructions

At implementation start:

1. Read repository instructions and inspect existing files before changing anything.
2. Save this approved plan and a detailed checklist in `tasks/`.
3. Maintain the exact gameplay definitions and scoring formulas above.
4. Implement one checklist item at a time and run its focused checks.
5. Record completed work, commands, evidence, and unresolved external setup.
6. Keep migrations, security policies, and tests with their feature slice.
7. After each major checkpoint, run the complete existing check suite.
8. Resume future sessions from the checklist instead of rebuilding completed work.

Do not replace multiplayer functionality with mock data, client-only scoring, simulated players, or placeholder authentication. Temporary development fixtures must be clearly separated from production behavior.

## 5. Verification, release readiness, and defaults

### Required automated scenarios

**Game rules**

- Four-player and eight-player rounds.
- One and two imposters, including invalid configurations.
- Strict-majority boundaries and ties.
- All scoring modes, mixed imposter outcomes, and fractional scores.
- Self-voting and invalid suspect counts.
- Out-of-turn, duplicate, invalid, and stale clue submissions.
- Extra passes preserving secrets and clearing ballots.
- Continuation ties and unanswered choices.
- Title minimums, ties, and perfect-performance exclusions.

**Multiplayer correctness**

- Two players racing for the eighth seat.
- A final vote racing with another player’s vote edit.
- Simultaneous deadline-advancement requests.
- Retries after a response is lost.
- Exactly-once scoring and statistics.
- Host transfer and participant reconnection.
- A departed player unable to continue reading room updates.
- Aborted rounds awarding no points.

**Privacy**

- Imposters cannot retrieve the secret word before reveal.
- Players cannot retrieve other assignments or ballots early.
- Hosts have no privileged access to hidden gameplay information.
- Nonmembers cannot read room data or join room channels.
- Clients cannot forge points, results, profile ownership, or roles.
- Uploaded files cannot bypass validation.
- Account deletion removes authentication and photos and anonymizes retained match records.

**End-to-end**

Run separate authenticated browser contexts for eight players through:

```text
Join → Ready → Roles → Clues → Vote → More clues
→ Clues → Revised vote → Roulette → Results
→ Next round → End match → Profile statistics
```

Also test continuation rejection leading directly to reveal, each scoring mode, browser refresh, network interruption, and background/resume on mobile.

### Release readiness

Prepare:

- HTTPS web hosting and direct invite-link handling.
- Separate development, staging, and production Supabase environments.
- EAS development, preview, and production build profiles.
- App icons, splash screen, package identifiers, permissions descriptions, and versioning.
- Real-device testing on iPhone and Android.
- TestFlight and Android internal-test build instructions.
- Privacy policy, terms, support contact, and account deletion flow.
- Reporting for names, clues, and avatars; host removal and persistent user blocking.
- Server-side basic prohibited-content filtering and an operator report-review procedure.
- Private image access and signed URLs rather than a public avatar directory.
- Structured operational errors and metrics for joins, command failures, disconnects, and finalization failures.
- Database backup, migration, and rollback instructions.

Verify current Apple and Google submission requirements before producing the release checklist. Store accounts, signing access, hosting credentials, and review approval are external dependencies; record them explicitly when unavailable.

### Defaults and completion standard

- English content only initially.
- Private rooms only.
- Discussion happens in person or through an external call; the app supplies sequential written clues.
- No built-in voice, general chat, public matchmaking, payments, ads, or elimination mechanics.
- Team scoring is the default; the host can choose another mode before a match.
- Match length is host-controlled; the host ends the match between rounds.
- Highest score wins; equal scores share the position.
- Preserve completed-round results when participants leave.
- Produce browser deployment artifacts and native build configurations; actual store publication remains a separate release action.

**Complete means:** the connected multiplayer flow works with eight independent sessions, all three scoring modes are verified, secrets remain private, reconnection is reliable, profiles persist, and web plus native preview builds have recorded validation evidence.
