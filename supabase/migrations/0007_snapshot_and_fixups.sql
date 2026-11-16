drop policy if exists "members read own roster" on public.room_members;
create policy "members read own roster" on public.room_members for select to authenticated using (
  exists (select 1 from public.room_members mine where mine.room_id = public.room_members.room_id and mine.user_id = auth.uid())
);
drop policy if exists "room members read room" on public.rooms;
create policy "room members read room" on public.rooms for select to authenticated using (
  exists (select 1 from public.room_members mine where mine.room_id = public.rooms.id and mine.user_id = auth.uid())
);
drop policy if exists "members read match" on public.matches;
create policy "members read match" on public.matches for select to authenticated using (
  exists (select 1 from public.room_members mine where mine.room_id = public.matches.room_id and mine.user_id = auth.uid())
);

create or replace function public.get_room_snapshot(p_room uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_room public.rooms;
begin
  if not exists(select 1 from public.room_members where room_id=p_room and user_id=auth.uid()) then raise exception 'NOT_A_MEMBER'; end if;
  select * into v_room from public.rooms where id=p_room;
  return jsonb_build_object(
    'id',v_room.id,'code',v_room.code,'host_id',v_room.host_id,'status',v_room.status,'scoring_mode',v_room.scoring_mode,'imposter_count',v_room.imposter_count,
    'members',(select coalesce(jsonb_agg(jsonb_build_object('id',m.user_id,'name',p.display_name,'seat',m.seat,'ready',m.ready) order by m.seat),'[]'::jsonb) from public.room_members m join public.profiles p on p.id=m.user_id where m.room_id=p_room),
    'round',(select jsonb_build_object('id',r.id,'match_id',r.match_id,'round_number',r.round_number,'phase',r.phase,'version',r.version,'clue_pass',r.clue_pass,'starting_user',r.starting_user,'reveal_at',r.reveal_at,'deadline_at',r.deadline_at,
      'clues',(select coalesce(jsonb_agg(jsonb_build_object('pass',c.clue_pass,'player_id',c.user_id,'player_name',p.display_name,'text',c.clue) order by c.clue_pass,c.id),'[]'::jsonb) from public.clues c join public.profiles p on p.id=c.user_id where c.round_id=r.id),
      'submitted_votes',(select count(distinct b.voter_id) from public.ballots b where b.round_id=r.id),
      'submitted_continuations',(select count(*) from public.continuation_votes cv where cv.round_id=r.id),
      'my_vote',(select coalesce(jsonb_agg(b.suspect_id),'[]'::jsonb) from public.ballots b where b.round_id=r.id and b.voter_id=auth.uid()),
      'word',(select secret_word from public.round_secrets where round_id=r.id and r.phase='results'),
      'results',(select coalesce(jsonb_agg(jsonb_build_object('player_id',rr.user_id,'name',p.display_name,'points',rr.points_half_units/2.0,'is_imposter',role.is_imposter,'caught',rr.caught,'hits',rr.hits,'fooled',rr.fooled,'votes',(select coalesce(jsonb_agg(jsonb_build_object('id',target.user_id,'name',tp.display_name) order by target.seat),'[]'::jsonb) from public.ballots b join public.room_members target on target.room_id=p_room and target.user_id=b.suspect_id join public.profiles tp on tp.id=target.user_id where b.round_id=r.id and b.voter_id=rr.user_id)) order by rm.seat),'[]'::jsonb) from public.round_results rr join public.round_roles role on role.round_id=rr.round_id and role.user_id=rr.user_id join public.profiles p on p.id=rr.user_id join public.room_members rm on rm.room_id=p_room and rm.user_id=rr.user_id where rr.round_id=r.id)
    ) from public.rounds r join public.matches ma on ma.id=r.match_id where ma.room_id=p_room order by r.round_number desc limit 1)
  );
end $$;

create or replace function public.advance_reveal(p_round uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists(select 1 from public.round_roles where round_id=p_round and user_id=auth.uid()) then raise exception 'NOT_A_PARTICIPANT'; end if;
  if not exists(select 1 from public.rounds where id=p_round and phase='reveal' and reveal_at<=now()-interval '4 seconds') then raise exception 'REVEAL_NOT_READY'; end if;
  perform public.finalize_round(p_round);
end $$;

revoke all on function public.advance_reveal(uuid),public.get_room_snapshot(uuid) from public;
grant execute on function public.advance_reveal(uuid),public.get_room_snapshot(uuid) to authenticated;
