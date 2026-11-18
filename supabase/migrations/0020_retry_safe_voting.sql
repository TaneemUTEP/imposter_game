-- The row lock serializes votes. Phase, not a client version, is the final-vote lock.
-- Serialize ballot writes on the round row. The server phase, not a stale
-- client version, decides whether another edit is still allowed.
create or replace function public.submit_ballot(p_round uuid,p_suspects uuid[],p_version bigint)
returns bigint language plpgsql security definer set search_path = '' as $$
declare r public.rounds; k int; n int;
begin
  select * into r from public.rounds where id=p_round for update;
  if r.id is null or r.phase<>'voting' then raise exception 'VOTING_LOCKED'; end if;
  if not exists(select 1 from public.round_roles where round_id=p_round and user_id=auth.uid()) then raise exception 'NOT_A_PARTICIPANT'; end if;
  select imposter_count into k from public.matches where id=r.match_id;
  if coalesce(cardinality(p_suspects),0)<>k or (select count(distinct x) from unnest(p_suspects) x)<>k then raise exception 'BALLOT_INVALID'; end if;
  if auth.uid()=any(p_suspects) or exists(select 1 from unnest(p_suspects) x where not exists(select 1 from public.round_roles where round_id=p_round and user_id=x)) then raise exception 'BALLOT_INVALID'; end if;
  delete from public.ballots where round_id=p_round and voter_id=auth.uid();
  insert into public.ballots(round_id,voter_id,suspect_id) select p_round,auth.uid(),x from unnest(p_suspects) x;
  select count(distinct voter_id) into n from public.ballots where round_id=p_round;
  if n=(select count(*) from public.round_roles where round_id=p_round) then
    update public.rounds set phase='continue_vote',deadline_at=now()+interval '15 seconds',version=version+1 where id=p_round returning version into r.version;
  else update public.rounds set version=version+1 where id=p_round returning version into r.version;
  end if;
  return r.version;
end $$;

-- Choices remain editable until the shared deadline; advancement is a separate
-- retry-safe operation so simultaneous clients cannot disagree on the outcome.
create or replace function public.choose_more_clues(p_round uuid,p_choice text,p_version bigint)
returns text language plpgsql security definer set search_path = '' as $$
declare r public.rounds;
begin
  select * into r from public.rounds where id=p_round for update;
  if r.id is null or r.phase<>'continue_vote' or now()>=r.deadline_at then raise exception 'VOTING_LOCKED'; end if;
  if not exists(select 1 from public.round_roles where round_id=p_round and user_id=auth.uid()) then raise exception 'NOT_A_PARTICIPANT'; end if;
  if p_choice not in ('more','reveal') then raise exception 'CHOICE_INVALID'; end if;
  insert into public.continuation_votes(round_id,user_id,choice) values(p_round,auth.uid(),p_choice)
    on conflict(round_id,user_id) do update set choice=excluded.choice,updated_at=now();
  -- Keep choices editable until the shared deadline, even when everyone has answered.
  update public.rounds set version=version+1 where id=p_round;
  return 'waiting';
end $$;

-- Resolve after the deadline using strict majority. Missing votes count as
-- reveal, and the row lock makes concurrent advancement calls safe.
create or replace function public.advance_continuation(p_round uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare r public.rounds; n int; more_count int;
begin
  select * into r from public.rounds where id=p_round for update;
  if not exists(select 1 from public.round_roles where round_id=p_round and user_id=auth.uid()) then raise exception 'NOT_A_PARTICIPANT'; end if;
  if r.phase<>'continue_vote' then return r.phase::text; end if;
  if r.deadline_at is null or now()<r.deadline_at then raise exception 'DEADLINE_NOT_REACHED'; end if;
  select count(*) into n from public.round_roles where round_id=p_round;
  select count(*) into more_count from public.continuation_votes where round_id=p_round and choice='more';
  if more_count>n/2 then
    delete from public.ballots where round_id=p_round;
    delete from public.continuation_votes where round_id=p_round;
    update public.rounds set phase='clues',clue_pass=clue_pass+1,version=version+1,
      starting_user=(select user_id from public.round_roles where round_id=p_round order by random() limit 1) where id=p_round;
    return 'more';
  end if;
  update public.rounds set phase='reveal',reveal_at=now(),version=version+1 where id=p_round;
  return 'reveal';
end $$;

revoke all on function public.submit_ballot(uuid,uuid[],bigint),public.choose_more_clues(uuid,text,bigint),public.advance_continuation(uuid) from public;
grant execute on function public.submit_ballot(uuid,uuid[],bigint),public.choose_more_clues(uuid,text,bigint),public.advance_continuation(uuid) to authenticated;
