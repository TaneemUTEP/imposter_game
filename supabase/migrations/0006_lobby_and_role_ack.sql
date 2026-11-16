create table public.role_acknowledgements (
  round_id uuid not null references public.rounds(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  acknowledged_at timestamptz not null default now(),
  primary key(round_id,user_id)
);
alter table public.role_acknowledgements enable row level security;

create or replace function public.set_ready(p_room uuid, p_ready boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.room_members set ready=p_ready where room_id=p_room and user_id=auth.uid();
  if not found then raise exception 'NOT_A_MEMBER'; end if;
end $$;

create or replace function public.update_room_settings(p_room uuid,p_mode public.scoring_mode,p_imposters smallint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.rooms set scoring_mode=p_mode,imposter_count=p_imposters,updated_at=now()
    where id=p_room and host_id=auth.uid() and status='lobby';
  if not found then raise exception 'HOST_REQUIRED_OR_ROOM_ACTIVE'; end if;
  if p_imposters not between 1 and 2 then raise exception 'IMPOSTER_COUNT_INVALID'; end if;
  if p_imposters=2 and (select count(*) from public.room_members where room_id=p_room)<5 then raise exception 'TOO_FEW_PLAYERS_FOR_TWO_IMPOSTERS'; end if;
end $$;

create or replace function public.acknowledge_role(p_round uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_phase public.round_phase; v_round public.rounds;
begin
  select * into v_round from public.rounds where id=p_round for update;
  if v_round.phase<>'roles' then raise exception 'ROUND_PHASE_INVALID'; end if;
  if not exists(select 1 from public.round_roles where round_id=p_round and user_id=auth.uid()) then raise exception 'NOT_A_PARTICIPANT'; end if;
  insert into public.role_acknowledgements(round_id,user_id) values(p_round,auth.uid()) on conflict do nothing;
  if (select count(*) from public.role_acknowledgements where round_id=p_round) = (select count(*) from public.round_roles where round_id=p_round) then
    update public.rounds set phase='clues',version=version+1 where id=p_round;
    return 'clues';
  end if;
  return 'waiting';
end $$;

create or replace function public.get_room_snapshot(p_room uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_room public.rooms;
begin
  if not exists(select 1 from public.room_members where room_id=p_room and user_id=auth.uid()) then raise exception 'NOT_A_MEMBER'; end if;
  select * into v_room from public.rooms where id=p_room;
  return jsonb_build_object(
    'id',v_room.id,'code',v_room.code,'host_id',v_room.host_id,'status',v_room.status,'scoring_mode',v_room.scoring_mode,'imposter_count',v_room.imposter_count,
    'members',(select coalesce(jsonb_agg(jsonb_build_object('id',m.user_id,'name',p.display_name,'seat',m.seat,'ready',m.ready) order by m.seat),'[]'::jsonb)
      from public.room_members m join public.profiles p on p.id=m.user_id where m.room_id=p_room),
    'round',(select to_jsonb(r) from public.rounds r join public.matches ma on ma.id=r.match_id where ma.room_id=p_room order by r.round_number desc limit 1)
  );
end $$;

create or replace function public.start_round(p_room uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_match uuid; v_round uuid; v_host uuid; v_count integer; v_imposters integer; v_number integer; v_first uuid; v_word text; v_hint text; v_status text;
begin
  select host_id,imposter_count,status into v_host,v_imposters,v_status from public.rooms where id=p_room for update;
  if v_host is null or v_host<>auth.uid() then raise exception 'HOST_REQUIRED'; end if;
  if v_status='active' and exists(select 1 from public.rounds r join public.matches ma on ma.id=r.match_id where ma.room_id=p_room and r.phase not in ('results','aborted')) then raise exception 'ROUND_IN_PROGRESS'; end if;
  select count(*) into v_count from public.room_members where room_id=p_room;
  if v_count not between 4 and 8 then raise exception 'ROOM_SIZE_INVALID'; end if;
  if v_imposters >= v_count then raise exception 'IMPOSTER_COUNT_INVALID'; end if;
  if exists(select 1 from public.room_members where room_id=p_room and not ready) then raise exception 'PLAYERS_NOT_READY'; end if;
  select id into v_match from public.matches where room_id=p_room and status='active' order by started_at desc limit 1;
  if v_match is null then insert into public.matches(room_id) values(p_room) returning id into v_match; end if;
  select coalesce(max(round_number),0)+1 into v_number from public.rounds where match_id=v_match;
  select user_id into v_first from public.room_members where room_id=p_room order by random() limit 1;
  insert into public.rounds(match_id,round_number,starting_user) values(v_match,v_number,v_first) returning id into v_round;
  insert into public.round_roles(round_id,user_id,is_imposter) select v_round,user_id,false from public.room_members where room_id=p_room;
  with chosen as(select user_id from public.room_members where room_id=p_room order by random() limit v_imposters)
  update public.round_roles rr set is_imposter=true from chosen c where rr.round_id=v_round and rr.user_id=c.user_id;
  select word,hint into v_word,v_hint from public.word_pairs order by random() limit 1;
  if v_word is null then raise exception 'WORD_POOL_EMPTY'; end if;
  insert into public.round_secrets(round_id,secret_word,hint) values(v_round,v_word,v_hint);
  update public.rooms set status='active' where id=p_room;
  return v_round;
end $$;

revoke all on function public.set_ready(uuid,boolean),public.update_room_settings(uuid,public.scoring_mode,smallint),public.acknowledge_role(uuid),public.get_room_snapshot(uuid) from public;
grant execute on function public.set_ready(uuid,boolean),public.update_room_settings(uuid,public.scoring_mode,smallint),public.acknowledge_role(uuid),public.get_room_snapshot(uuid) to authenticated;
