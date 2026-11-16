create or replace function public.create_room(p_display_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_room public.rooms;
  v_code text;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if char_length(trim(p_display_name)) not between 1 and 24 then raise exception 'NAME_INVALID'; end if;
  insert into public.profiles(id, display_name) values (v_user, trim(p_display_name))
    on conflict (id) do update set display_name = excluded.display_name;
  loop
    v_code := upper(translate(encode(gen_random_bytes(5), 'base64'), '+/=', 'XYZ'));
    v_code := left(regexp_replace(v_code, '[^A-Z2-9]', '', 'g'), 6);
    if char_length(v_code) = 6 and not exists (select 1 from public.rooms where code = v_code and status <> 'closed') then exit; end if;
  end loop;
  insert into public.rooms(code, host_id) values (v_code, v_user) returning * into v_room;
  insert into public.room_members(room_id, user_id, seat) values (v_room.id, v_user, 1);
  return jsonb_build_object('room_id', v_room.id, 'code', v_code, 'host_id', v_user);
end;
$$;

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
  select seat into v_seat from generate_series(1, 8) seat
    where not exists (select 1 from public.room_members where room_id = v_room.id and room_members.seat = seat)
    order by seat limit 1;
  if v_seat is null then raise exception 'ROOM_FULL'; end if;
  insert into public.profiles(id, display_name) values (v_user, trim(p_display_name))
    on conflict (id) do update set display_name = excluded.display_name;
  insert into public.room_members(room_id, user_id, seat) values (v_room.id, v_user, v_seat);
  return jsonb_build_object('room_id', v_room.id, 'code', v_room.code);
end;
$$;

revoke all on function public.create_room(text) from public;
revoke all on function public.join_room(text, text) from public;
grant execute on function public.create_room(text) to authenticated;
grant execute on function public.join_room(text, text) to authenticated;
