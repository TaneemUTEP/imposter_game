create or replace function public.finalize_round(p_round uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_round public.rounds;
  v_room uuid;
  v_mode public.scoring_mode;
  v_imposter_count integer;
  v_civilians integer;
  v_player record;
  v_hits integer;
  v_correct integer;
  v_caught boolean;
  v_points numeric;
begin
  if not exists(select 1 from public.round_roles where round_id=p_round and user_id=auth.uid()) then raise exception 'NOT_A_PARTICIPANT'; end if;
  select * into v_round from public.rounds where id=p_round for update;
  if v_round.phase='results' then return; end if;
  if v_round.phase<>'reveal' then raise exception 'ROUND_NOT_REVEALED'; end if;
  select ma.room_id,r.scoring_mode,r.imposter_count into v_room,v_mode,v_imposter_count
    from public.matches ma join public.rooms r on r.id=ma.room_id where ma.id=v_round.match_id;
  select count(*) into v_civilians from public.round_roles where round_id=p_round and not is_imposter;
  for v_player in select user_id,is_imposter from public.round_roles where round_id=p_round loop
    select count(*) into v_hits from public.ballots b join public.round_roles role on role.round_id=b.round_id and role.user_id=b.suspect_id and role.is_imposter where b.round_id=p_round and b.suspect_id=v_player.user_id;
    v_caught := v_hits > v_civilians/2.0;
    select count(*) into v_correct from public.ballots b join public.round_roles role on role.round_id=b.round_id and role.user_id=b.suspect_id and role.is_imposter where b.round_id=p_round and b.voter_id=v_player.user_id;
    if v_player.is_imposter then
      if v_caught then v_points:=0;
      elsif v_mode='deception' then v_points:=v_civilians-v_hits;
      else v_points:=1;
      end if;
    elsif v_mode='team' then
      v_points:=case when (select count(*) from public.round_roles role where role.round_id=p_round and role.is_imposter and (select count(*) from public.ballots b where b.round_id=p_round and b.suspect_id=role.user_id)>v_civilians/2.0) = v_imposter_count then 1 else 0 end;
    else v_points:=v_correct::numeric/v_imposter_count;
    end if;
    insert into public.round_results(round_id,user_id,points_half_units,caught,hits,fooled)
      values(p_round,v_player.user_id,round(v_points*2)::integer,case when v_player.is_imposter then v_caught else null end,v_hits,v_civilians-v_hits)
      on conflict(round_id,user_id) do nothing;
  end loop;
  update public.rounds set phase='results',version=version+1 where id=p_round;
end $$;

revoke all on function public.finalize_round(uuid) from public;
grant execute on function public.finalize_round(uuid) to authenticated;
