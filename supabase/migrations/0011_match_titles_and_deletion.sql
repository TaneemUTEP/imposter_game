create or replace function public.finish_match(p_match uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room uuid; v_titles jsonb;
begin
  select room_id into v_room from public.matches where id=p_match and status='active' for update;
  if v_room is null then raise exception 'MATCH_NOT_ACTIVE'; end if;
  if not exists(select 1 from public.rooms where id=v_room and host_id=auth.uid()) then raise exception 'HOST_REQUIRED'; end if;
  if exists(select 1 from public.rounds where match_id=p_match and phase not in ('results','aborted')) then raise exception 'ROUND_IN_PROGRESS'; end if;
  update public.matches set status='finished',finished_at=now() where id=p_match;
  with stats as (
    select role.user_id,
      count(*) filter(where not role.is_imposter) as civ_rounds,
      count(*) filter(where role.is_imposter) as imp_rounds,
      sum(case when not role.is_imposter then (select count(*) from public.ballots b join public.round_roles target on target.round_id=b.round_id and target.user_id=b.suspect_id and target.is_imposter where b.round_id=rr.round_id and b.voter_id=rr.user_id) else 0 end) as correct,
      sum(case when not role.is_imposter then (select count(*) from public.ballots b where b.round_id=rr.round_id and b.voter_id=rr.user_id) else 0 end) as possible,
      count(*) filter(where role.is_imposter and not coalesce(rr.caught,true)) as escapes,
      count(*) filter(where role.is_imposter and not coalesce(rr.caught,true) and rr.hits=0) as invisible
    from public.round_results rr join public.round_roles role on role.round_id=rr.round_id and role.user_id=rr.user_id
    join public.rounds r on r.id=rr.round_id where r.match_id=p_match group by role.user_id
  ), civ as (select *,correct::numeric/nullif(possible,0) accuracy from stats where civ_rounds>=3 and possible>0), imp as (select *,escapes::numeric/nullif(imp_rounds,0) escape_rate from stats where imp_rounds>=2)
  insert into public.achievements(user_id,match_id,title)
  select user_id,p_match,title from (
    (select user_id,'Sharp Eye'::text title from civ where accuracy=(select max(accuracy) from civ))
    union all (select user_id,'Wild Guesser' from civ where accuracy=(select min(accuracy) from civ) and accuracy<1)
    union all (select user_id,'Master of Disguise' from imp where escape_rate=(select max(escape_rate) from imp))
    union all (select user_id,'Caught in the Act' from imp where escape_rate=(select min(escape_rate) from imp) and escape_rate<1)
    union all (select user_id,'Invisible Imposter' from stats where invisible>0)
  ) awards on conflict do nothing;
  select coalesce(jsonb_agg(jsonb_build_object('player_id',a.user_id,'name',p.display_name,'title',a.title) order by p.display_name,a.title),'[]'::jsonb)
    into v_titles from public.achievements a join public.profiles p on p.id=a.user_id where a.match_id=p_match;
  return v_titles;
end $$;

create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=auth.uid();
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  delete from storage.objects where bucket_id='avatars' and (storage.foldername(name))[1]=v_user::text;
  delete from auth.users where id=v_user;
end $$;

revoke all on function public.finish_match(uuid),public.delete_my_account() from public;
grant execute on function public.finish_match(uuid),public.delete_my_account() to authenticated;
