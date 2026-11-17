create policy "room members use private channels" on realtime.messages
for select to authenticated using (
  case when realtime.topic() ~ '^room:[0-9a-fA-F-]{36}$'
    then public.can_access_room(split_part(realtime.topic(),':',2)::uuid) else false end
);
create policy "room members send private broadcasts" on realtime.messages
for insert to authenticated with check (
  case when realtime.topic() ~ '^room:[0-9a-fA-F-]{36}$'
    then public.can_access_room(split_part(realtime.topic(),':',2)::uuid) else false end
);

do $$
declare t text;
begin
  if not exists(select 1 from pg_publication where pubname='supabase_realtime') then return; end if;
  foreach t in array array['rooms','room_members','rounds','room_waitlist'] loop
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
      execute format('alter publication supabase_realtime add table public.%I',t);
    end if;
  end loop;
end $$;
