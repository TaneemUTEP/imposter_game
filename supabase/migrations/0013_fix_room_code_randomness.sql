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
    v_code := upper(translate(encode(extensions.gen_random_bytes(5), 'base64'), '+/=', 'XYZ'));
    v_code := left(regexp_replace(v_code, '[^A-Z2-9]', '', 'g'), 6);
    if char_length(v_code) = 6 and not exists (select 1 from public.rooms where code = v_code and status <> 'closed') then exit; end if;
  end loop;
  insert into public.rooms(code, host_id) values (v_code, v_user) returning * into v_room;
  insert into public.room_members(room_id, user_id, seat) values (v_room.id, v_user, 1);
  return jsonb_build_object('room_id', v_room.id, 'code', v_code, 'host_id', v_user);
end;
$$;
