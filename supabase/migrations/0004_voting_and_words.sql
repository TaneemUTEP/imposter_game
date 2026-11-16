create table public.word_pairs (
  id bigint generated always as identity primary key,
  category text not null,
  word text not null,
  hint text not null,
  unique (category, word)
);
alter table public.word_pairs enable row level security;

insert into public.word_pairs(category,word,hint) values
('Food','Pancake','A breakfast food'),('Food','Watermelon','A summer fruit'),('Food','Popcorn','A movie snack'),('Food','Cinnamon','A warm spice'),('Food','Sushi','A Japanese dish'),
('Animals','Penguin','A bird that swims'),('Animals','Giraffe','A tall animal'),('Animals','Octopus','A sea creature'),('Animals','Hedgehog','A small spiky animal'),('Animals','Flamingo','A pink wading bird'),
('Places','Lighthouse','A coastal structure'),('Places','Airport','A travel hub'),('Places','Museum','A place for exhibits'),('Places','Desert','A dry landscape'),('Places','Library','A quiet place with books'),
('Objects','Umbrella','Used in rainy weather'),('Objects','Telescope','Used to see far away'),('Objects','Backpack','Carried on your shoulders'),('Objects','Hourglass','A timekeeping object'),('Objects','Compass','Helps with directions'),
('Nature','Volcano','A mountain that can erupt'),('Nature','Rainbow','Appears after rain'),('Nature','Glacier','A slow-moving ice mass'),('Nature','Thunder','A sound during storms'),('Nature','Sunflower','A bright garden plant'),
('Activities','Skateboarding','A street sport'),('Activities','Camping','Sleeping outdoors'),('Activities','Knitting','A yarn craft'),('Activities','Archery','A bow and arrow sport'),('Activities','Karaoke','Singing along to music');

create or replace function public.submit_ballot(p_round uuid, p_suspects uuid[], p_version bigint)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_round public.rounds; v_room uuid; v_expected integer; v_count integer;
begin
  select * into v_round from public.rounds where id=p_round for update;
  if v_round.phase <> 'voting' or v_round.version <> p_version then raise exception 'VOTING_LOCKED'; end if;
  if not exists (select 1 from public.round_roles where round_id=p_round and user_id=auth.uid()) then raise exception 'NOT_A_PARTICIPANT'; end if;
  select room_id into v_room from public.matches where id=v_round.match_id;
  select imposter_count into v_expected from public.rooms where id=v_room;
  if coalesce(array_length(p_suspects,1),0) <> v_expected or (select count(distinct x) from unnest(p_suspects) x) <> v_expected then raise exception 'BALLOT_INVALID'; end if;
  if auth.uid() = any(p_suspects) or exists(select 1 from unnest(p_suspects) x where not exists(select 1 from public.room_members where room_id=v_room and user_id=x)) then raise exception 'BALLOT_INVALID'; end if;
  delete from public.ballots where round_id=p_round and voter_id=auth.uid();
  insert into public.ballots(round_id,voter_id,suspect_id) select p_round,auth.uid(),x from unnest(p_suspects) x;
  select count(distinct voter_id) into v_count from public.ballots where round_id=p_round;
  if v_count = (select count(*) from public.round_roles where round_id=p_round) then
    update public.rounds set phase='continue_vote', deadline_at=now()+interval '15 seconds', version=version+1 where id=p_round returning version into v_round.version;
  else update public.rounds set version=version+1 where id=p_round returning version into v_round.version;
  end if;
  return v_round.version;
end $$;

create or replace function public.choose_more_clues(p_round uuid, p_choice text, p_version bigint)
returns text language plpgsql security definer set search_path = '' as $$
declare v_round public.rounds; v_count integer; v_more integer; v_players integer;
begin
  select * into v_round from public.rounds where id=p_round for update;
  if v_round.phase <> 'continue_vote' or v_round.version <> p_version or now() >= v_round.deadline_at then raise exception 'VOTING_LOCKED'; end if;
  if p_choice not in ('more','reveal') then raise exception 'CHOICE_INVALID'; end if;
  insert into public.continuation_votes(round_id,user_id,choice) values(p_round,auth.uid(),p_choice)
    on conflict(round_id,user_id) do update set choice=excluded.choice,updated_at=now();
  select count(*) into v_players from public.round_roles where round_id=p_round;
  select count(*) into v_count from public.continuation_votes where round_id=p_round;
  select count(*) into v_more from public.continuation_votes where round_id=p_round and choice='more';
  if v_count=v_players then
    if v_more > v_players/2 then
      delete from public.ballots where round_id=p_round;
      delete from public.continuation_votes where round_id=p_round;
      update public.rounds set phase='clues',clue_pass=clue_pass+1,version=version+1,starting_user=(select user_id from public.round_roles where round_id=p_round order by random() limit 1) where id=p_round;
      return 'more';
    end if;
    update public.rounds set phase='reveal',reveal_at=now(),version=version+1 where id=p_round;
    return 'reveal';
  end if;
  update public.rounds set version=version+1 where id=p_round;
  return 'waiting';
end $$;

revoke all on function public.submit_ballot(uuid,uuid[],bigint),public.choose_more_clues(uuid,text,bigint) from public;
grant execute on function public.submit_ballot(uuid,uuid[],bigint),public.choose_more_clues(uuid,text,bigint) to authenticated;
