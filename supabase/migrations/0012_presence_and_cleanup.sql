alter table public.room_members add column if not exists last_seen_at timestamptz not null default now();
alter table public.room_members add column if not exists disconnected_at timestamptz;

create or replace function public.heartbeat_room(p_room uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.room_members set last_seen_at=now(),disconnected_at=null where room_id=p_room and user_id=auth.uid();
  if not found then raise exception 'NOT_A_MEMBER'; end if;
end $$;

create or replace function public.reconcile_room(p_room uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_room public.rooms; v_match uuid; v_round uuid; v_host_stale boolean;
begin
  select * into v_room from public.rooms where id=p_room for update;
  if v_room.id is null or not public.is_room_member(p_room) then raise exception 'NOT_A_MEMBER'; end if;
  update public.room_members set disconnected_at=coalesce(disconnected_at,last_seen_at)
    where room_id=p_room and last_seen_at < now()-interval '60 seconds';
  update public.room_members set disconnected_at=null where room_id=p_room and last_seen_at>=now()-interval '60 seconds';
  select disconnected_at < now()-interval '60 seconds' into v_host_stale from public.room_members where room_id=p_room and user_id=v_room.host_id;
  if coalesce(v_host_stale,false) then
    update public.rooms set host_id=(select user_id from public.room_members where room_id=p_room and disconnected_at is null order by joined_at limit 1) where id=p_room;
  end if;
  select id into v_match from public.matches where room_id=p_room and status='active' order by started_at desc limit 1;
  if v_match is null then return; end if;
  select id into v_round from public.rounds where match_id=v_match and phase not in ('results','aborted') order by round_number desc limit 1;
  if v_round is not null and exists(select 1 from public.room_members where room_id=p_room and disconnected_at < now()-interval '120 seconds') then
    update public.rounds set phase='aborted',version=version+1 where id=v_round;
    update public.rooms set status='lobby' where id=p_room;
  end if;
end $$;

create or replace function public.leave_room(p_room uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_room public.rooms;
begin
  select * into v_room from public.rooms where id=p_room for update;
  if not exists(select 1 from public.room_members where room_id=p_room and user_id=auth.uid()) then return; end if;
  if exists(select 1 from public.rounds r join public.matches ma on ma.id=r.match_id where ma.room_id=p_room and r.phase not in ('results','aborted')) then
    update public.rounds r set phase='aborted',version=version+1 from public.matches ma where r.match_id=ma.id and ma.room_id=p_room and r.phase not in ('results','aborted');
    update public.rooms set status='lobby' where id=p_room;
  end if;
  delete from public.room_members where room_id=p_room and user_id=auth.uid();
  if v_room.host_id=auth.uid() then
    update public.rooms set host_id=(select user_id from public.room_members where room_id=p_room order by joined_at limit 1) where id=p_room;
  end if;
  if not exists(select 1 from public.room_members where room_id=p_room) then update public.rooms set status='closed' where id=p_room; end if;
end $$;

revoke all on function public.heartbeat_room(uuid),public.reconcile_room(uuid),public.leave_room(uuid) from public;
grant execute on function public.heartbeat_room(uuid),public.reconcile_room(uuid),public.leave_room(uuid) to authenticated;

create or replace function public.advance_continuation(p_round uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_round public.rounds; v_players integer; v_more integer;
begin
  select * into v_round from public.rounds where id=p_round for update;
  if v_round.phase<>'continue_vote' or v_round.deadline_at is null or now()<v_round.deadline_at then raise exception 'DEADLINE_NOT_REACHED'; end if;
  if not exists(select 1 from public.round_roles where round_id=p_round and user_id=auth.uid()) then raise exception 'NOT_A_PARTICIPANT'; end if;
  select count(*) into v_players from public.round_roles where round_id=p_round;
  select count(*) into v_more from public.continuation_votes where round_id=p_round and choice='more';
  if v_more>v_players/2 then
    delete from public.ballots where round_id=p_round;
    delete from public.continuation_votes where round_id=p_round;
    update public.rounds set phase='clues',clue_pass=clue_pass+1,version=version+1,starting_user=(select user_id from public.round_roles where round_id=p_round order by random() limit 1) where id=p_round;
    return 'more';
  end if;
  update public.rounds set phase='reveal',reveal_at=now(),version=version+1 where id=p_round;
  return 'reveal';
end $$;
revoke all on function public.advance_continuation(uuid) from public;
grant execute on function public.advance_continuation(uuid) to authenticated;
