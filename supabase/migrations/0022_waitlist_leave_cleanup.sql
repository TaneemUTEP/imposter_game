-- Explicit leave removes the caller from room membership. Abort an unfinished
-- round rather than allowing a missing player to deadlock its phase; close an
-- empty room and safely hand host ownership to a remaining seated member.
create or replace function public.leave_room(p_room uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.rooms; next_host uuid;
begin
  select * into r from public.rooms where id=p_room for update;
  if r.id is null then return; end if;
  delete from public.room_waitlist where room_id=p_room and user_id=auth.uid();
  if not exists(select 1 from public.room_members where room_id=p_room and user_id=auth.uid()) then return; end if;
  if exists(select 1 from public.rounds rr join public.matches m on m.id=rr.match_id where m.room_id=p_room and rr.phase not in ('results','aborted')) then
    update public.rounds rr set phase='aborted',version=version+1 from public.matches m
      where rr.match_id=m.id and m.room_id=p_room and rr.phase not in ('results','aborted');
    update public.rooms set status='lobby' where id=p_room;
  end if;
  delete from public.room_members where room_id=p_room and user_id=auth.uid();
  if r.host_id=auth.uid() then
    select user_id into next_host from public.room_members where room_id=p_room order by joined_at,user_id limit 1;
    if next_host is null then
      select user_id into next_host from public.room_waitlist where room_id=p_room order by requested_at,user_id limit 1;
      if next_host is not null then
        insert into public.room_members(room_id,user_id,seat,ready)
          values(p_room,next_host,1,(select ready from public.room_waitlist where room_id=p_room and user_id=next_host));
        delete from public.room_waitlist where room_id=p_room and user_id=next_host;
      end if;
    end if;
    if next_host is not null then update public.rooms set host_id=next_host where id=p_room; end if;
  end if;
  if not exists(select 1 from public.room_members where room_id=p_room) then update public.rooms set status='closed' where id=p_room; end if;
end $$;

-- Return only the authenticated caller's role/secret details after verifying
-- membership in this round's frozen roster. Never expose other roles here.
create or replace function public.get_private_round(p_round uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare role_row public.round_roles; secret_row public.round_secrets; round_row public.rounds; duration interval; k int;
begin
  select * into role_row from public.round_roles where round_id=p_round and user_id=auth.uid();
  if not found then raise exception 'NOT_A_PARTICIPANT'; end if;
  select * into round_row from public.rounds where id=p_round;
  select imposter_count into k from public.matches where id=round_row.match_id;
  duration:=interval '4 seconds'+((k-1)*interval '1.5 seconds');
  select * into secret_row from public.round_secrets where round_id=p_round;
  if round_row.phase='results' or (round_row.phase='reveal' and round_row.reveal_at+duration<=now()) then
    return jsonb_build_object('is_imposter',role_row.is_imposter,'word',secret_row.secret_word,'hint',secret_row.hint);
  end if;
  if role_row.is_imposter then return jsonb_build_object('is_imposter',true,'hint',secret_row.hint); end if;
  return jsonb_build_object('is_imposter',false,'word',secret_row.secret_word);
end $$;

revoke all on function public.leave_room(uuid),public.get_private_round(uuid) from public;
grant execute on function public.leave_room(uuid),public.get_private_round(uuid) to authenticated;
