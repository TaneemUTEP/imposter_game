create or replace function public.join_room(p_code text, p_display_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_room public.rooms;
  v_seat integer;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if char_length(trim(p_display_name)) not between 1 and 24 then raise exception 'NAME_INVALID'; end if;
  select * into v_room from public.rooms where code = upper(trim(p_code)) and status <> 'closed' for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  if exists (select 1 from public.room_members where room_id = v_room.id and user_id = v_user) then
    return jsonb_build_object('room_id', v_room.id, 'code', v_room.code);
  end if;
  if v_room.status <> 'lobby' then raise exception 'ROOM_IN_PROGRESS'; end if;
  select candidate.seat into v_seat
    from generate_series(1, 8) as candidate(seat)
    where not exists (
      select 1 from public.room_members as member
      where member.room_id = v_room.id and member.seat = candidate.seat
    )
    order by candidate.seat
    limit 1;
  if v_seat is null then raise exception 'ROOM_FULL'; end if;
  insert into public.profiles(id, display_name) values (v_user, trim(p_display_name))
    on conflict (id) do update set display_name = excluded.display_name;
  insert into public.room_members(room_id, user_id, seat) values (v_room.id, v_user, v_seat);
  return jsonb_build_object('room_id', v_room.id, 'code', v_room.code);
end;
$$;
