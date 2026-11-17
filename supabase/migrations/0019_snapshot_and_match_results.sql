create or replace function public.get_room_snapshot(p_room uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare room_row public.rooms; round_row public.rounds; waiting boolean;
begin
  if not public.can_access_room(p_room) then raise exception 'NOT_A_MEMBER'; end if;
  select * into room_row from public.rooms where id=p_room;
  waiting:=not exists(select 1 from public.room_members where room_id=p_room and user_id=auth.uid());
  select r.* into round_row from public.rounds r join public.matches m on m.id=r.match_id
    where m.room_id=p_room order by r.round_number desc limit 1;
  return jsonb_build_object(
    'id',room_row.id,'code',room_row.code,'host_id',room_row.host_id,'status',room_row.status,
    'scoring_mode',room_row.scoring_mode,'imposter_count',room_row.imposter_count,
    'enabled_categories',room_row.enabled_categories,'is_waiting',waiting,
    'match_titles',(select coalesce(jsonb_agg(jsonb_build_object('player_id',a.user_id,'name',p.display_name,'title',a.title) order by p.display_name,a.title),'[]'::jsonb)
      from public.achievements a join public.profiles p on p.id=a.user_id where a.match_id=round_row.match_id),
    'members',(select coalesce(jsonb_agg(jsonb_build_object('id',m.user_id,'name',p.display_name,'seat',m.seat,'ready',m.ready) order by m.seat),'[]'::jsonb)
       from public.room_members m join public.profiles p on p.id=m.user_id where m.room_id=p_room),
    'waiting',(select coalesce(jsonb_agg(jsonb_build_object('id',w.user_id,'name',p.display_name,'ready',w.ready,'requested_at',w.requested_at) order by w.requested_at),'[]'::jsonb)
       from public.room_waitlist w join public.profiles p on p.id=w.user_id where w.room_id=p_room),
    'round',case when round_row.id is null or waiting then null else jsonb_build_object(
      'id',round_row.id,'match_id',round_row.match_id,'match_status',(select status from public.matches where id=round_row.match_id),'round_number',round_row.round_number,'phase',round_row.phase,
      'version',round_row.version,'clue_pass',round_row.clue_pass,'starting_user',round_row.starting_user,
      'reveal_at',round_row.reveal_at,'deadline_at',round_row.deadline_at,
      'clues',(select coalesce(jsonb_agg(jsonb_build_object('pass',c.clue_pass,'player_id',c.user_id,'player_name',rr.display_name,'text',c.clue) order by c.clue_pass,c.id),'[]'::jsonb)
        from public.clues c join public.round_roles rr on rr.round_id=c.round_id and rr.user_id=c.user_id where c.round_id=round_row.id),
      'submitted_votes',(select count(distinct b.voter_id) from public.ballots b where b.round_id=round_row.id),
      'submitted_voters',(select coalesce(jsonb_agg(b.voter_id),'[]'::jsonb) from public.ballots b where b.round_id=round_row.id group by b.round_id),
      'submitted_continuations',(select count(*) from public.continuation_votes cv where cv.round_id=round_row.id),
      'my_continuation',(select choice from public.continuation_votes where round_id=round_row.id and user_id=auth.uid()),
      'my_vote',(select coalesce(jsonb_agg(b.suspect_id),'[]'::jsonb) from public.ballots b where b.round_id=round_row.id and b.voter_id=auth.uid()),
      'revealed_imposters',(select coalesce(jsonb_agg(role.user_id order by role.seat),'[]'::jsonb) from (
        select rr.user_id,rr.seat,row_number() over(order by rr.seat) n from public.round_roles rr where rr.round_id=round_row.id and rr.is_imposter
      ) role where round_row.phase='results' or (round_row.phase='reveal' and round_row.reveal_at+interval '4 seconds'+((role.n-1)*interval '1.5 seconds')<=now())),
      'word',(select secret_word from public.round_secrets where round_id=round_row.id and round_row.phase='results'),
      'hint',(select hint from public.round_secrets where round_id=round_row.id and round_row.phase='results'),
      'results',(select coalesce(jsonb_agg(jsonb_build_object(
         'player_id',rr.user_id,'name',role.display_name,'seat',role.seat,'points',rr.points_half_units/2.0,
         'match_points',(select coalesce(sum(allr.points_half_units),0)/2.0 from public.round_results allr join public.rounds ar on ar.id=allr.round_id where ar.match_id=round_row.match_id and allr.user_id=rr.user_id),
         'is_imposter',role.is_imposter,'caught',rr.caught,'hits',rr.hits,'fooled',rr.fooled,
         'correct_picks',(select count(*) from public.ballots b join public.round_roles target on target.round_id=b.round_id and target.user_id=b.suspect_id and target.is_imposter where b.round_id=rr.round_id and b.voter_id=rr.user_id),
         'votes',(select coalesce(jsonb_agg(jsonb_build_object('id',target.user_id,'name',target.display_name) order by target.seat),'[]'::jsonb)
            from public.ballots b join public.round_roles target on target.round_id=b.round_id and target.user_id=b.suspect_id where b.round_id=rr.round_id and b.voter_id=rr.user_id)
       ) order by role.seat),'[]'::jsonb) from public.round_results rr join public.round_roles role on role.round_id=rr.round_id and role.user_id=rr.user_id where rr.round_id=round_row.id)
    ) end
  );
end $$;

create or replace function public.finish_match(p_match uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare room_id uuid; titles jsonb;
begin
  select m.room_id into room_id from public.matches m where m.id=p_match and m.status='active' for update;
  if room_id is null then
    select m.room_id into room_id from public.matches m where m.id=p_match and m.status='finished';
    if room_id is null then raise exception 'MATCH_NOT_ACTIVE'; end if;
    if not exists(select 1 from public.rooms where id=room_id and host_id=auth.uid()) then raise exception 'HOST_REQUIRED'; end if;
    return (select coalesce(jsonb_agg(jsonb_build_object('player_id',a.user_id,'name',p.display_name,'title',a.title) order by p.display_name,a.title),'[]'::jsonb) from public.achievements a join public.profiles p on p.id=a.user_id where a.match_id=p_match);
  end if;
  if not exists(select 1 from public.rooms where id=room_id and host_id=auth.uid()) then raise exception 'HOST_REQUIRED'; end if;
  if exists(select 1 from public.rounds where match_id=p_match and phase not in ('results','aborted')) then raise exception 'ROUND_IN_PROGRESS'; end if;
  update public.matches set status='finished',finished_at=coalesce(finished_at,now()) where id=p_match;
  update public.rooms set status='lobby',updated_at=now() where id=room_id;
  with stats as (
    select role.user_id,
      count(*) filter(where not role.is_imposter) civ_rounds,
      count(*) filter(where role.is_imposter) imp_rounds,
      sum(case when not role.is_imposter then (select count(*) from public.ballots b join public.round_roles target on target.round_id=b.round_id and target.user_id=b.suspect_id and target.is_imposter where b.round_id=rr.round_id and b.voter_id=rr.user_id) else 0 end) correct,
      sum(case when not role.is_imposter then (select count(*) from public.round_roles where round_id=rr.round_id and is_imposter) else 0 end) possible,
      count(*) filter(where role.is_imposter and not coalesce(rr.caught,true)) escapes,
      count(*) filter(where role.is_imposter and not coalesce(rr.caught,true) and rr.hits=0) invisible,
      bool_or(not role.is_imposter and (select count(*) from public.ballots b join public.round_roles target on target.round_id=b.round_id and target.user_id=b.suspect_id and target.is_imposter where b.round_id=rr.round_id and b.voter_id=rr.user_id)=(select count(*) from public.round_roles where round_id=rr.round_id and is_imposter)) perfect
    from public.round_results rr join public.round_roles role on role.round_id=rr.round_id and role.user_id=rr.user_id
    join public.rounds r on r.id=rr.round_id where r.match_id=p_match group by role.user_id
  ), civ as(select *,correct::numeric/nullif(possible,0) accuracy from stats where civ_rounds>=3 and possible>0),
  imp as(select *,escapes::numeric/nullif(imp_rounds,0) escape_rate from stats where imp_rounds>=2),
  awards as(
    select user_id,'Sharp Eye'::text title from civ where accuracy=(select max(accuracy) from civ)
    union all select user_id,'Wild Guesser' from civ where accuracy=(select min(accuracy) from civ) and accuracy<1
    union all select user_id,'Master of Disguise' from imp where escape_rate=(select max(escape_rate) from imp)
    union all select user_id,'Caught in the Act' from imp where escape_rate=(select min(escape_rate) from imp) and escape_rate<1
    union all select user_id,'Invisible Imposter' from stats where invisible>0
    union all select user_id,'Perfect Read' from stats where perfect
  )
  insert into public.achievements(user_id,match_id,title) select user_id,p_match,title from awards on conflict do nothing;
  select coalesce(jsonb_agg(jsonb_build_object('player_id',a.user_id,'name',p.display_name,'title',a.title) order by p.display_name,a.title),'[]'::jsonb)
    into titles from public.achievements a join public.profiles p on p.id=a.user_id where a.match_id=p_match;
  return titles;
end $$;

revoke all on function public.get_room_snapshot(uuid),public.finish_match(uuid) from public;
grant execute on function public.get_room_snapshot(uuid),public.finish_match(uuid) to authenticated;
