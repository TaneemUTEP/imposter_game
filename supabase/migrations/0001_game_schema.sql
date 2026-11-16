create extension if not exists pgcrypto;

create type public.scoring_mode as enum ('team', 'partial', 'deception');
create type public.round_phase as enum ('roles', 'clues', 'discussion', 'voting', 'continue_vote', 'reveal', 'results', 'aborted');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 24),
  avatar_path text,
  created_at timestamptz not null default now()
);

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  host_id uuid not null references auth.users(id),
  status text not null default 'lobby' check (status in ('lobby', 'active', 'closed')),
  scoring_mode public.scoring_mode not null default 'team',
  imposter_count smallint not null default 1 check (imposter_count between 1 and 2),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.room_members (
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  seat smallint not null check (seat between 1 and 8),
  ready boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id),
  unique (room_id, seat)
);

create table public.matches (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  status text not null default 'active' check (status in ('active', 'finished')),
  started_at timestamptz not null default now(),
  finished_at timestamptz
);

create table public.rounds (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  round_number integer not null,
  phase public.round_phase not null default 'roles',
  version bigint not null default 1,
  starting_user uuid not null references auth.users(id),
  clue_pass integer not null default 1,
  deadline_at timestamptz,
  reveal_at timestamptz,
  created_at timestamptz not null default now(),
  unique (match_id, round_number)
);

-- Secret word and roles are deliberately isolated from client-readable tables.
create table public.round_secrets (
  round_id uuid primary key references public.rounds(id) on delete cascade,
  secret_word text not null,
  hint text not null,
  created_at timestamptz not null default now()
);

create table public.round_roles (
  round_id uuid not null references public.rounds(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  is_imposter boolean not null,
  primary key (round_id, user_id)
);

create table public.clues (
  id bigint generated always as identity primary key,
  round_id uuid not null references public.rounds(id) on delete cascade,
  clue_pass integer not null,
  user_id uuid not null references auth.users(id),
  clue text not null check (char_length(clue) between 1 and 30),
  submitted_at timestamptz not null default now(),
  unique (round_id, clue_pass, user_id)
);

create table public.ballots (
  round_id uuid not null references public.rounds(id) on delete cascade,
  voter_id uuid not null references auth.users(id),
  suspect_id uuid not null references auth.users(id),
  submitted_at timestamptz not null default now(),
  primary key (round_id, voter_id, suspect_id),
  check (voter_id <> suspect_id)
);

create table public.continuation_votes (
  round_id uuid not null references public.rounds(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  choice text not null check (choice in ('more', 'reveal')),
  updated_at timestamptz not null default now(),
  primary key (round_id, user_id)
);

create table public.round_results (
  round_id uuid not null references public.rounds(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  points_half_units integer not null default 0,
  caught boolean,
  hits integer not null default 0,
  fooled integer not null default 0,
  primary key (round_id, user_id)
);

create index room_members_user_idx on public.room_members(user_id);
create index rounds_match_idx on public.rounds(match_id, round_number);
create index clues_round_idx on public.clues(round_id, clue_pass);

alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.matches enable row level security;
alter table public.rounds enable row level security;
alter table public.round_secrets enable row level security;
alter table public.round_roles enable row level security;
alter table public.clues enable row level security;
alter table public.ballots enable row level security;
alter table public.continuation_votes enable row level security;
alter table public.round_results enable row level security;

create policy "profile read" on public.profiles for select to authenticated using (true);
create policy "profile owner insert" on public.profiles for insert to authenticated with check (id = auth.uid());
create policy "profile owner update" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "room members read room" on public.rooms for select to authenticated using (
  exists (select 1 from public.room_members m where m.room_id = id and m.user_id = auth.uid())
);
create policy "members read own roster" on public.room_members for select to authenticated using (
  exists (select 1 from public.room_members m where m.room_id = room_id and m.user_id = auth.uid())
);
create policy "members read match" on public.matches for select to authenticated using (
  exists (select 1 from public.room_members m where m.room_id = room_id and m.user_id = auth.uid())
);
create policy "members read round state" on public.rounds for select to authenticated using (
  exists (select 1 from public.matches ma join public.room_members rm on rm.room_id = ma.room_id where ma.id = match_id and rm.user_id = auth.uid())
);
create policy "members read clues" on public.clues for select to authenticated using (
  exists (select 1 from public.rounds r join public.matches ma on ma.id = r.match_id join public.room_members rm on rm.room_id = ma.room_id where r.id = round_id and rm.user_id = auth.uid())
);
create policy "voter sees own ballot" on public.ballots for select to authenticated using (voter_id = auth.uid());
create policy "voter sees own continuation" on public.continuation_votes for select to authenticated using (user_id = auth.uid());
create policy "members read results after reveal" on public.round_results for select to authenticated using (
 exists (select 1 from public.rounds r join public.matches ma on ma.id = r.match_id join public.room_members rm on rm.room_id = ma.room_id where r.id = round_id and r.phase = 'results' and rm.user_id = auth.uid())
);

-- There are intentionally no client SELECT policies for round_secrets or round_roles.
-- Mutations and private role reads are exposed only through validated security-definer RPCs.
