create or replace function public.is_room_member(p_room uuid,p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.room_members m where m.room_id=p_room and m.user_id=p_user)
$$;
revoke all on function public.is_room_member(uuid,uuid) from public;
grant execute on function public.is_room_member(uuid,uuid) to authenticated;

drop policy if exists "room members read room" on public.rooms;
create policy "room members read room" on public.rooms for select to authenticated using (public.is_room_member(id));
drop policy if exists "members read own roster" on public.room_members;
create policy "members read own roster" on public.room_members for select to authenticated using (public.is_room_member(room_id));
drop policy if exists "members read match" on public.matches;
create policy "members read match" on public.matches for select to authenticated using (public.is_room_member(room_id));
drop policy if exists "members read round state" on public.rounds;
create policy "members read round state" on public.rounds for select to authenticated using (
  exists(select 1 from public.matches ma where ma.id=match_id and public.is_room_member(ma.room_id))
);
drop policy if exists "members read clues" on public.clues;
create policy "members read clues" on public.clues for select to authenticated using (
  exists(select 1 from public.rounds r join public.matches ma on ma.id=r.match_id where r.id=round_id and public.is_room_member(ma.room_id))
);
drop policy if exists "members read results after reveal" on public.round_results;
create policy "members read results after reveal" on public.round_results for select to authenticated using (
  exists(select 1 from public.rounds r join public.matches ma on ma.id=r.match_id where r.id=round_id and r.phase='results' and public.is_room_member(ma.room_id))
);
