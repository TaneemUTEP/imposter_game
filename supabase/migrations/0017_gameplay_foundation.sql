alter table public.rooms
  add column enabled_categories text[] not null default array['Food','Animals','Places','Objects','Nature','Activities'],
  add column create_command_id uuid;

alter table public.matches
  add column scoring_mode public.scoring_mode not null default 'team',
  add column imposter_count smallint not null default 1,
  add column word_categories text[] not null default array['Food','Animals','Places','Objects','Nature','Activities'];

update public.matches ma
set scoring_mode=r.scoring_mode, imposter_count=r.imposter_count, word_categories=r.enabled_categories
from public.rooms r where r.id=ma.room_id;

alter table public.matches add constraint matches_imposter_count_check check (imposter_count between 1 and 2);
alter table public.matches add constraint matches_categories_check check (
  cardinality(word_categories) between 1 and 6 and
  word_categories <@ array['Food','Animals','Places','Objects','Nature','Activities']::text[]
);
alter table public.rooms add constraint rooms_categories_check check (
  cardinality(enabled_categories) between 1 and 6 and
  enabled_categories <@ array['Food','Animals','Places','Objects','Nature','Activities']::text[]
);
create unique index rooms_create_command_unique on public.rooms(host_id,create_command_id) where create_command_id is not null;

alter table public.rounds add column room_id uuid references public.rooms(id), add column start_command_id uuid;
update public.rounds ro set room_id=ma.room_id from public.matches ma where ma.id=ro.match_id;
alter table public.rounds alter column room_id set not null;
create index rounds_room_idx on public.rounds(room_id,round_number desc);
create unique index rounds_start_command_unique on public.rounds(start_command_id) where start_command_id is not null;

alter table public.round_roles add column seat smallint, add column display_name text;
with numbered as (
  select rr.round_id,rr.user_id,rm.seat as old_seat,p.display_name,
    row_number() over(partition by rr.round_id order by rm.seat nulls last,rr.user_id)::smallint as new_seat
  from public.round_roles rr
  left join public.room_members rm on rm.room_id=(select ro.room_id from public.rounds ro where ro.id=rr.round_id) and rm.user_id=rr.user_id
  join public.profiles p on p.id=rr.user_id
)
update public.round_roles rr set seat=n.new_seat,display_name=n.display_name from numbered n
where rr.round_id=n.round_id and rr.user_id=n.user_id;
alter table public.round_roles alter column seat set not null, alter column display_name set not null;
alter table public.round_roles add constraint round_roles_seat_check check (seat between 1 and 8);
create unique index round_roles_round_seat_unique on public.round_roles(round_id,seat);

create table public.room_waitlist (
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  requested_at timestamptz not null default now(),
  primary key(room_id,user_id)
);
alter table public.room_waitlist enable row level security;
create policy "room waitlist read" on public.room_waitlist for select to authenticated
  using (user_id=auth.uid() or public.is_room_member(room_id));

create table public.game_rate_limits (
  user_id uuid not null references auth.users(id) on delete cascade,
  action text not null check(action in ('create_room','join_room')),
  bucket_start timestamptz not null,
  requests integer not null check(requests > 0),
  primary key(user_id,action,bucket_start)
);
alter table public.game_rate_limits enable row level security;

create or replace function public.normalize_game_word(p_text text)
returns text language sql immutable parallel safe set search_path = '' as $$
  select regexp_replace(lower(trim(coalesce(p_text,''))), '[^[:alnum:]]', '', 'g');
$$;
revoke all on function public.normalize_game_word(text) from public;

alter table public.word_pairs add constraint word_pair_category_check check(category in ('Food','Animals','Places','Objects','Nature','Activities'));
alter table public.word_pairs add constraint word_pair_hint_no_answer_check check (
  public.normalize_game_word(word) <> '' and
  position(public.normalize_game_word(word) in public.normalize_game_word(hint))=0
);
create unique index word_pairs_normalized_word_unique on public.word_pairs(public.normalize_game_word(word));

create or replace function public.is_room_member(p_room uuid,p_user uuid default auth.uid())
returns boolean language plpgsql stable security definer set search_path = '' as $$
begin
  if p_user is not null and p_user<>auth.uid() then return false; end if;
  return exists(select 1 from public.room_members m where m.room_id=p_room and m.user_id=auth.uid());
end $$;
revoke all on function public.is_room_member(uuid,uuid) from public;
grant execute on function public.is_room_member(uuid,uuid) to authenticated;

create or replace function public.can_access_room(p_room uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_room_member(p_room) or exists(
    select 1 from public.room_waitlist w where w.room_id=p_room and w.user_id=auth.uid()
  )
$$;
revoke all on function public.can_access_room(uuid) from public;
grant execute on function public.can_access_room(uuid) to authenticated;
