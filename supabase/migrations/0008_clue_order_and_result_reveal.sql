create or replace function public.submit_clue(p_round uuid, p_clue text, p_version bigint)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_round public.rounds; v_expected uuid; v_offset integer; v_start_seat integer; v_room uuid;
begin
  select * into v_round from public.rounds where id=p_round for update;
  if v_round.phase<>'clues' or v_round.version<>p_version then raise exception 'STALE_STATE'; end if;
  select ma.room_id into v_room from public.matches ma where ma.id=v_round.match_id;
  select seat into v_start_seat from public.room_members where room_id=v_room and user_id=v_round.starting_user;
  select count(*) into v_offset from public.clues where round_id=p_round and clue_pass=v_round.clue_pass;
  select user_id into v_expected from public.room_members where room_id=v_room order by mod(seat-v_start_seat+8,8) offset v_offset limit 1;
  if v_expected<>auth.uid() then raise exception 'NOT_YOUR_TURN'; end if;
  if char_length(trim(p_clue)) not between 1 and 30 or p_clue ~ '\s' then raise exception 'CLUE_INVALID'; end if;
  if lower(trim(p_clue))=lower((select secret_word from public.round_secrets where round_id=p_round)) then raise exception 'CLUE_REVEALS_WORD'; end if;
  insert into public.clues(round_id,clue_pass,user_id,clue) values(p_round,v_round.clue_pass,auth.uid(),trim(p_clue));
  update public.rounds set version=version+1 where id=p_round returning version into v_round.version;
  if (select count(*) from public.clues where round_id=p_round and clue_pass=v_round.clue_pass)=(select count(*) from public.round_roles where round_id=p_round) then
    update public.rounds set phase='voting',version=version+1 where id=p_round returning version into v_round.version;
  end if;
  return v_round.version;
end $$;

revoke all on function public.submit_clue(uuid,text,bigint) from public;
grant execute on function public.submit_clue(uuid,text,bigint) to authenticated;
