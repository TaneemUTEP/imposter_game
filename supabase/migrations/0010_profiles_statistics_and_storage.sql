alter table public.profiles add column if not exists avatar_path text;
alter table public.profiles add column if not exists updated_at timestamptz not null default now();
create table public.achievements (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  match_id uuid references public.matches(id) on delete cascade,
  title text not null,
  awarded_at timestamptz not null default now(),
  unique(user_id,match_id,title)
);
alter table public.achievements enable row level security;
create policy "owner reads own achievements" on public.achievements for select to authenticated using(user_id=auth.uid());

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('avatars','avatars',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
create policy "avatar owner read" on storage.objects for select to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "avatar owner upload" on storage.objects for insert to authenticated with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "avatar owner replace" on storage.objects for update to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text) with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);

create or replace function public.get_my_profile()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_profile public.profiles; v_rounds integer; v_imposter_rounds integer; v_escapes integer; v_correct integer; v_available integer; v_fooled integer;
begin
  select * into v_profile from public.profiles where id=auth.uid();
  select count(*),count(*) filter(where role.is_imposter),count(*) filter(where role.is_imposter and not coalesce(rr.caught,true))
    into v_rounds,v_imposter_rounds,v_escapes
    from public.round_results rr join public.round_roles role on role.round_id=rr.round_id and role.user_id=rr.user_id where rr.user_id=auth.uid();
  select count(*) filter(where not voter.is_imposter),count(*) filter(where not voter.is_imposter and target.is_imposter)
    into v_available,v_correct from public.ballots b join public.round_roles target on target.round_id=b.round_id and target.user_id=b.suspect_id
    join public.round_roles voter on voter.round_id=b.round_id and voter.user_id=b.voter_id where b.voter_id=auth.uid();
  select coalesce(sum(rr.fooled),0) into v_fooled from public.round_results rr join public.round_roles role on role.round_id=rr.round_id and role.user_id=rr.user_id where rr.user_id=auth.uid() and role.is_imposter;
  return jsonb_build_object('id',v_profile.id,'display_name',v_profile.display_name,'avatar_path',v_profile.avatar_path,
    'rounds',v_rounds,'imposter_rounds',v_imposter_rounds,'escapes',v_escapes,'escape_rate',case when v_imposter_rounds=0 then null else round(v_escapes::numeric/v_imposter_rounds,3) end,
    'correct',v_correct,'available',v_available,'accuracy',case when v_available=0 then null else round(v_correct::numeric/v_available,3) end,'fooled',v_fooled,
    'achievements',(select coalesce(jsonb_agg(jsonb_build_object('title',title,'awarded_at',awarded_at) order by awarded_at desc),'[]'::jsonb) from public.achievements where user_id=auth.uid()));
end $$;
revoke all on function public.get_my_profile() from public;
grant execute on function public.get_my_profile() to authenticated;

create or replace function public.update_my_profile(p_name text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if char_length(trim(p_name)) not between 1 and 24 then raise exception 'NAME_INVALID'; end if;
  update public.profiles set display_name=trim(p_name),updated_at=now() where id=auth.uid();
  if not found then raise exception 'PROFILE_NOT_FOUND'; end if;
end $$;
revoke all on function public.update_my_profile(text) from public;
grant execute on function public.update_my_profile(text) to authenticated;
