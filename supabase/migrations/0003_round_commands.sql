create or replace function public.start_round(p_room uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_match uuid;
  v_round uuid;
  v_host uuid;
  v_count integer;
  v_imposters integer;
  v_number integer;
  v_first uuid;
  v_word text;
  v_hint text;
begin
  select host_id, imposter_count into v_host, v_imposters from public.rooms where id = p_room and status = 'lobby' for update;
  if v_host is null or v_host <> auth.uid() then raise exception 'HOST_REQUIRED'; end if;
  select count(*) into v_count from public.room_members where room_id = p_room;
  if v_count < 4 or v_count > 8 then raise exception 'ROOM_SIZE_INVALID'; end if;
  if v_imposters >= v_count then raise exception 'IMPOSTER_COUNT_INVALID'; end if;
  select id into v_match from public.matches where room_id = p_room and status = 'active' order by started_at desc limit 1;
  if v_match is null then insert into public.matches(room_id) values (p_room) returning id into v_match; end if;
  select coalesce(max(round_number), 0) + 1 into v_number from public.rounds where match_id = v_match;
  select user_id into v_first from public.room_members where room_id = p_room order by random() limit 1;
  insert into public.rounds(match_id, round_number, starting_user) values (v_match, v_number, v_first) returning id into v_round;
  insert into public.round_roles(round_id, user_id, is_imposter)
    select v_round, user_id, false from public.room_members where room_id = p_room;
  with chosen as (select user_id from public.room_members where room_id = p_room order by random() limit v_imposters)
  update public.round_roles rr set is_imposter = true from chosen c where rr.round_id = v_round and rr.user_id = c.user_id;
  select word, hint into v_word, v_hint from public.word_pairs order by random() limit 1;
  if v_word is null then raise exception 'WORD_POOL_EMPTY'; end if;
  insert into public.round_secrets(round_id, secret_word, hint) values (v_round, v_word, v_hint);
  update public.rooms set status = 'active' where id = p_room;
  return v_round;
end;
$$;

create or replace function public.get_private_round(p_round uuid)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare v_role public.round_roles; v_secret public.round_secrets; v_phase public.round_phase;
begin
  select rr.* into v_role from public.round_roles rr where rr.round_id = p_round and rr.user_id = auth.uid();
  if not found then raise exception 'NOT_A_PARTICIPANT'; end if;
  select phase into v_phase from public.rounds where id = p_round;
  select * into v_secret from public.round_secrets where round_id = p_round;
  if v_phase in ('reveal', 'results') then
    return jsonb_build_object('is_imposter', v_role.is_imposter, 'word', v_secret.secret_word, 'hint', v_secret.hint);
  end if;
  if v_role.is_imposter then return jsonb_build_object('is_imposter', true, 'hint', v_secret.hint); end if;
  return jsonb_build_object('is_imposter', false, 'word', v_secret.secret_word);
end;
$$;

create or replace function public.submit_clue(p_round uuid, p_clue text, p_version bigint)
returns bigint
language plpgsql security definer
set search_path = ''
as $$
declare v_round public.rounds; v_expected uuid;
begin
  select * into v_round from public.rounds where id = p_round for update;
  if v_round.phase <> 'clues' or v_round.version <> p_version then raise exception 'STALE_STATE'; end if;
  select rm.user_id into v_expected from public.matches ma join public.room_members rm on rm.room_id = ma.room_id
    where ma.id = v_round.match_id order by rm.seat offset (select count(*) from public.clues where round_id=p_round and clue_pass=v_round.clue_pass) limit 1;
  if v_expected <> auth.uid() then raise exception 'NOT_YOUR_TURN'; end if;
  if char_length(trim(p_clue)) not between 1 and 30 or p_clue ~ '\s' then raise exception 'CLUE_INVALID'; end if;
  if lower(trim(p_clue)) = lower((select secret_word from public.round_secrets where round_id=p_round)) then raise exception 'CLUE_REVEALS_WORD'; end if;
  insert into public.clues(round_id, clue_pass, user_id, clue) values(p_round, v_round.clue_pass, auth.uid(), trim(p_clue));
  update public.rounds set version=version+1 where id=p_round returning version into v_round.version;
  if (select count(*) from public.clues where round_id=p_round and clue_pass=v_round.clue_pass) =
     (select count(*) from public.round_roles where round_id=p_round) then
    update public.rounds set phase='voting', version=version+1 where id=p_round returning version into v_round.version;
  end if;
  return v_round.version;
end;
$$;

revoke all on function public.start_round(uuid), public.get_private_round(uuid), public.submit_clue(uuid,text,bigint) from public;
grant execute on function public.start_round(uuid), public.get_private_round(uuid), public.submit_clue(uuid,text,bigint) to authenticated;
