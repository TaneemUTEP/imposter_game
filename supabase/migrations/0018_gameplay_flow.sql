-- Server authoritative room configuration and round lifecycle.
alter table public.round_roles add column if not exists display_name text;
alter table public.round_roles add column if not exists seat smallint;
alter table public.room_waitlist add column ready boolean not null default false;

create or replace function public.set_ready(p_room uuid,p_ready boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.room_members set ready=p_ready where room_id=p_room and user_id=auth.uid();
  if found then return; end if;
  update public.room_waitlist set ready=p_ready where room_id=p_room and user_id=auth.uid();
  if not found then raise exception 'NOT_A_MEMBER'; end if;
end $$;

create or replace function public.check_game_rate_limit(p_action text)
returns void language plpgsql security definer set search_path = '' as $$
declare bucket timestamptz; total int; maximum int;
begin
  if p_action not in ('create_room','join_room') then raise exception 'RATE_ACTION_INVALID'; end if;
  bucket:=to_timestamp(floor(extract(epoch from now())/600)*600);
  maximum:=case when p_action='create_room' then 5 else 20 end;
  insert into public.game_rate_limits as limits(user_id,action,bucket_start,requests)
    values(auth.uid(),p_action,bucket,1)
    on conflict(user_id,action,bucket_start) do update set requests=limits.requests+1
    returning requests into total;
  if total>maximum then raise exception 'RATE_LIMITED'; end if;
end $$;

create or replace function public.create_room(p_display_name text,p_command_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare u uuid:=auth.uid(); r public.rooms; v_code text; random_bytes bytea; i int;
begin
  if u is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_command_id is null then raise exception 'COMMAND_ID_REQUIRED'; end if;
  if char_length(trim(p_display_name)) not between 1 and 24 then raise exception 'NAME_INVALID'; end if;
  select * into r from public.rooms where host_id=u and create_command_id=p_command_id;
  if r.id is not null then return jsonb_build_object('room_id',r.id,'code',r.code,'host_id',u); end if;
  perform public.check_game_rate_limit('create_room');
  insert into public.profiles(id,display_name) values(u,trim(p_display_name)) on conflict(id) do update set display_name=excluded.display_name;
  loop
    random_bytes:=extensions.gen_random_bytes(6); v_code:='';
    for i in 0..5 loop v_code:=v_code||substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',(get_byte(random_bytes,i)&31)+1,1); end loop;
    if not exists(select 1 from public.rooms where rooms.code=v_code) then exit; end if;
  end loop;
  insert into public.rooms(code,host_id,create_command_id) values(v_code,u,p_command_id)
    on conflict(host_id,create_command_id) where create_command_id is not null do nothing returning * into r;
  if r.id is null then
    select * into r from public.rooms where host_id=u and create_command_id=p_command_id;
    return jsonb_build_object('room_id',r.id,'code',r.code,'host_id',u);
  end if;
  insert into public.room_members(room_id,user_id,seat) values(r.id,u,1);
  return jsonb_build_object('room_id',r.id,'code',r.code,'host_id',u,'waiting',false);
end $$;

create or replace function public.update_room_settings(
  p_room uuid, p_mode public.scoring_mode, p_imposters smallint, p_categories text[]
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_mode not in ('team','partial','deception') then raise exception 'SCORING_MODE_INVALID'; end if;
  if p_imposters not between 1 and 2 then raise exception 'IMPOSTER_COUNT_INVALID'; end if;
  if coalesce(cardinality(p_categories),0) not between 1 and 6 or
     p_categories <@ array['Food','Animals','Places','Objects','Nature','Activities']::text[] is not true then
    raise exception 'CATEGORIES_INVALID';
  end if;
  update public.rooms set scoring_mode=p_mode,imposter_count=p_imposters,enabled_categories=p_categories,updated_at=now()
    where id=p_room and host_id=auth.uid() and status='lobby';
  if not found then raise exception 'HOST_REQUIRED_OR_ROOM_ACTIVE'; end if;
  if p_imposters=2 and (select count(*) from public.room_members where room_id=p_room)<5 then
    raise exception 'TOO_FEW_PLAYERS_FOR_TWO_IMPOSTERS';
  end if;
end $$;

create or replace function public.start_round(p_room uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_room public.rooms; v_match uuid; v_round uuid; v_number int; v_word text; v_hint text;
begin
  select * into v_room from public.rooms where id=p_room and status in ('lobby','active') for update;
  if v_room.id is null or v_room.host_id<>auth.uid() then raise exception 'HOST_REQUIRED'; end if;
  if exists(select 1 from public.rounds r join public.matches m on m.id=r.match_id
            where m.room_id=p_room and m.status='active' and r.phase not in ('results','aborted')) then
    raise exception 'ROUND_IN_PROGRESS';
  end if;
  -- Seat waiting players only between rounds, never over the eight-player cap.
  with slots as (
    select s as seat,row_number() over(order by s) as rn from generate_series(1,8) s
    where not exists(select 1 from public.room_members rm where rm.room_id=p_room and rm.seat=s)
  ), queued as (
    select w.user_id,w.ready,row_number() over(order by w.requested_at,w.user_id) as rn from public.room_waitlist w
    where w.room_id=p_room
  )
  insert into public.room_members(room_id,user_id,seat,ready)
    select p_room,q.user_id,s.seat,q.ready from queued q join slots s using(rn)
    on conflict(room_id,user_id) do nothing;
  delete from public.room_waitlist w where w.room_id=p_room and exists(
    select 1 from public.room_members rm where rm.room_id=p_room and rm.user_id=w.user_id
  );
  if (select count(*) from public.room_members where room_id=p_room) not between 4 and 8 then raise exception 'ROOM_SIZE_INVALID'; end if;
  if v_room.imposter_count=2 and (select count(*) from public.room_members where room_id=p_room)<5 then raise exception 'TOO_FEW_PLAYERS_FOR_TWO_IMPOSTERS'; end if;
  if exists(select 1 from public.room_members where room_id=p_room and not ready) then raise exception 'PLAYERS_NOT_READY'; end if;
  select id into v_match from public.matches where room_id=p_room and status='active' for update;
  if v_match is null then
    insert into public.matches(room_id,scoring_mode,imposter_count,word_categories)
      values(p_room,v_room.scoring_mode,v_room.imposter_count,v_room.enabled_categories) returning id into v_match;
  end if;
  select coalesce(max(round_number),0)+1 into v_number from public.rounds where match_id=v_match;
  select wp.word,wp.hint into v_word,v_hint from public.word_pairs wp
    where wp.category=any((select word_categories from public.matches where id=v_match))
      and not exists(select 1 from public.rounds oldr join public.round_secrets oldsec on oldsec.round_id=oldr.id
                     where oldr.match_id=v_match and oldsec.secret_word=wp.word)
    order by random() limit 1;
  if v_word is null then
    select word,hint into v_word,v_hint from public.word_pairs where category=any(v_room.enabled_categories) order by random() limit 1;
  end if;
  if v_word is null then raise exception 'WORD_POOL_EMPTY'; end if;
  insert into public.rounds(match_id,room_id,round_number,starting_user)
    select v_match,p_room,v_number,user_id from public.room_members where room_id=p_room order by random() limit 1
    returning id into v_round;
  insert into public.round_roles(round_id,user_id,is_imposter,seat,display_name)
    select v_round,rm.user_id,false,rm.seat,p.display_name from public.room_members rm join public.profiles p on p.id=rm.user_id where rm.room_id=p_room;
  with chosen as (select user_id from public.round_roles where round_id=v_round order by random() limit (select imposter_count from public.matches where id=v_match))
    update public.round_roles rr set is_imposter=true from chosen c where rr.round_id=v_round and rr.user_id=c.user_id;
  insert into public.round_secrets(round_id,secret_word,hint) values(v_round,v_word,v_hint);
  update public.room_members set ready=false where room_id=p_room;
  update public.rooms set status='active' where id=p_room;
  return v_round;
end $$;

create or replace function public.choose_more_clues(p_round uuid,p_choice text,p_version bigint)
returns text language plpgsql security definer set search_path = '' as $$
declare r public.rounds; n int; more_count int;
begin
  select * into r from public.rounds where id=p_round for update;
  if r.phase<>'continue_vote' or r.version<>p_version or now()>=r.deadline_at then raise exception 'VOTING_LOCKED'; end if;
  if not exists(select 1 from public.round_roles where round_id=p_round and user_id=auth.uid()) then raise exception 'NOT_A_PARTICIPANT'; end if;
  if p_choice not in ('more','reveal') then raise exception 'CHOICE_INVALID'; end if;
  insert into public.continuation_votes(round_id,user_id,choice) values(p_round,auth.uid(),p_choice)
    on conflict(round_id,user_id) do update set choice=excluded.choice,updated_at=now();
  select count(*) into n from public.round_roles where round_id=p_round;
  select count(*) into more_count from public.continuation_votes where round_id=p_round and choice='more';
  if (select count(*) from public.continuation_votes where round_id=p_round)=n then
    if more_count>n/2 then
      delete from public.ballots where round_id=p_round;
      delete from public.continuation_votes where round_id=p_round;
      update public.rounds set phase='clues',clue_pass=clue_pass+1,version=version+1,
        starting_user=(select user_id from public.round_roles where round_id=p_round order by random() limit 1) where id=p_round;
      return 'more';
    end if;
    update public.rounds set phase='reveal',reveal_at=now(),version=version+1 where id=p_round;
    return 'reveal';
  end if;
  update public.rounds set version=version+1 where id=p_round;
  return 'waiting';
end $$;

create or replace function public.submit_clue(p_round uuid,p_clue text,p_version bigint)
returns bigint language plpgsql security definer set search_path = '' as $$
declare r public.rounds; expected uuid; normalized text;
begin
  select * into r from public.rounds where id=p_round for update;
  if r.phase<>'clues' then raise exception 'ROUND_PHASE_INVALID'; end if;
  if not exists(select 1 from public.round_roles where round_id=p_round and user_id=auth.uid()) then raise exception 'NOT_A_PARTICIPANT'; end if;
  if r.version<>p_version then raise exception 'STALE_STATE'; end if;
  select user_id into expected from public.round_roles where round_id=p_round
    order by ((seat-(select seat from public.round_roles where round_id=p_round and user_id=r.starting_user)+8)%8),seat
    offset (select count(*) from public.clues where round_id=p_round and clue_pass=r.clue_pass) limit 1;
  if expected<>auth.uid() then raise exception 'NOT_YOUR_TURN'; end if;
  if char_length(trim(p_clue)) not between 1 and 30 or trim(p_clue) ~ '[[:space:]]' or p_clue ~* '(https?://|www\.|[[:alnum:]._-]+\.(com|net|org|io|app)(/|$))' then raise exception 'CLUE_INVALID'; end if;
  normalized:=public.normalize_game_word(p_clue);
  if normalized='' or normalized=public.normalize_game_word((select secret_word from public.round_secrets where round_id=p_round)) then raise exception 'CLUE_REVEALS_WORD'; end if;
  insert into public.clues(round_id,clue_pass,user_id,clue) values(p_round,r.clue_pass,auth.uid(),trim(p_clue));
  update public.rounds set version=version+1 where id=p_round returning version into r.version;
  if (select count(*) from public.clues where round_id=p_round and clue_pass=r.clue_pass)=(select count(*) from public.round_roles where round_id=p_round) then
    update public.rounds set phase='voting',version=version+1 where id=p_round returning version into r.version;
  end if;
  return r.version;
end $$;

create or replace function public.finalize_round(p_round uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.rounds; mode public.scoring_mode; k int; civilians int; pl record; hits int; correct int; caught bool; pts numeric; reveal_duration interval;
begin
  select * into r from public.rounds where id=p_round for update;
  if not exists(select 1 from public.round_roles where round_id=p_round and user_id=auth.uid()) then raise exception 'NOT_A_PARTICIPANT'; end if;
  if r.phase='results' then return; end if;
  if r.phase<>'reveal' then raise exception 'ROUND_NOT_REVEALED'; end if;
  select scoring_mode,imposter_count into mode,k from public.matches where id=r.match_id;
  reveal_duration:=interval '4 seconds'+((k-1)*interval '1.5 seconds');
  if r.reveal_at is null or r.reveal_at+reveal_duration>now() then raise exception 'REVEAL_NOT_READY'; end if;
  select count(*) into civilians from public.round_roles where round_id=p_round and not is_imposter;
  for pl in select user_id,is_imposter from public.round_roles where round_id=p_round loop
    select count(*) into hits from public.ballots b join public.round_roles role on role.round_id=b.round_id and role.user_id=b.voter_id
      where b.round_id=p_round and b.suspect_id=pl.user_id and not role.is_imposter;
    caught:=hits>civilians/2.0;
    select count(*) into correct from public.ballots b join public.round_roles role on role.round_id=b.round_id and role.user_id=b.suspect_id
      where b.round_id=p_round and b.voter_id=pl.user_id and role.is_imposter;
    if pl.is_imposter then
      pts:=case when caught then 0 when mode='deception' then civilians-hits else 1 end;
    elsif mode='team' then
      pts:=case when (select count(*) from public.round_roles impost where impost.round_id=p_round and impost.is_imposter and
           (select count(*) from public.ballots b join public.round_roles voter on voter.round_id=b.round_id and voter.user_id=b.voter_id
            where b.round_id=p_round and b.suspect_id=impost.user_id and not voter.is_imposter)>civilians/2.0)=k then 1 else 0 end;
    else pts:=correct::numeric/k; end if;
    insert into public.round_results(round_id,user_id,points_half_units,caught,hits,fooled)
      values(p_round,pl.user_id,round(pts*2)::int,case when pl.is_imposter then caught else null end,hits,civilians-hits)
      on conflict(round_id,user_id) do nothing;
  end loop;
  update public.rounds set phase='results',version=version+1 where id=p_round;
end $$;

create or replace function public.advance_reveal(p_round uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.rounds; k int; duration interval;
begin
  select * into r from public.rounds where id=p_round for update;
  if not exists(select 1 from public.round_roles where round_id=p_round and user_id=auth.uid()) then raise exception 'NOT_A_PARTICIPANT'; end if;
  if r.phase='results' then return; end if;
  select m.imposter_count into k from public.matches m where m.id=r.match_id;
  duration:=interval '4 seconds'+((k-1)*interval '1.5 seconds');
  if r.phase<>'reveal' or r.reveal_at>now()-duration then raise exception 'REVEAL_NOT_READY'; end if;
  perform public.finalize_round(p_round);
end $$;

-- An active round admits a player to the waitlist; the room's eight-seat cap includes both lists.
create or replace function public.join_room(p_code text,p_display_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare u uuid:=auth.uid(); r public.rooms; seat_no int;
begin
  if u is null then raise exception 'AUTH_REQUIRED'; end if;
  if char_length(trim(p_display_name)) not between 1 and 24 then raise exception 'NAME_INVALID'; end if;
  select * into r from public.rooms where code=upper(trim(p_code)) and status<>'closed' for update;
  if r.id is null then raise exception 'ROOM_NOT_FOUND'; end if;
  if exists(select 1 from public.room_members where room_id=r.id and user_id=u) then return jsonb_build_object('room_id',r.id,'code',r.code,'waiting',false); end if;
  if exists(select 1 from public.room_waitlist where room_id=r.id and user_id=u) then return jsonb_build_object('room_id',r.id,'code',r.code,'waiting',true); end if;
  perform public.check_game_rate_limit('join_room');
  if (select count(*) from public.room_members where room_id=r.id)+(select count(*) from public.room_waitlist where room_id=r.id)>=8 then raise exception 'ROOM_FULL'; end if;
  insert into public.profiles(id,display_name) values(u,trim(p_display_name)) on conflict(id) do update set display_name=excluded.display_name;
  if exists(select 1 from public.rounds ro join public.matches m on m.id=ro.match_id where m.room_id=r.id and m.status='active' and ro.phase not in ('results','aborted')) then
    insert into public.room_waitlist(room_id,user_id) values(r.id,u);
    return jsonb_build_object('room_id',r.id,'code',r.code,'waiting',true);
  end if;
  select s into seat_no from generate_series(1,8) s where not exists(select 1 from public.room_members m where m.room_id=r.id and m.seat=s) order by s limit 1;
  if seat_no is null then raise exception 'ROOM_FULL'; end if;
  insert into public.room_members(room_id,user_id,seat) values(r.id,u,seat_no);
  return jsonb_build_object('room_id',r.id,'code',r.code,'waiting',false);
end $$;

revoke all on function public.update_room_settings(uuid,public.scoring_mode,smallint,text[]),public.start_round(uuid),public.choose_more_clues(uuid,text,bigint),public.submit_clue(uuid,text,bigint),public.finalize_round(uuid),public.advance_reveal(uuid),public.join_room(text,text) from public;
revoke all on function public.set_ready(uuid,boolean) from public;
revoke all on function public.create_room(text),public.check_game_rate_limit(text) from public,authenticated;
grant execute on function public.update_room_settings(uuid,public.scoring_mode,smallint,text[]),public.start_round(uuid),public.choose_more_clues(uuid,text,bigint),public.submit_clue(uuid,text,bigint),public.finalize_round(uuid),public.advance_reveal(uuid),public.join_room(text,text),public.set_ready(uuid,boolean),public.create_room(text,uuid) to authenticated;

drop policy if exists "room waitlist read" on public.room_waitlist;
create policy "room waitlist read" on public.room_waitlist for select to authenticated using(public.can_access_room(room_id));
grant select on public.room_waitlist to authenticated;

-- Word assets: add 120 unique original pairs; six categories remain balanced.
insert into public.word_pairs(category,word,hint) values
('Food','Burrito','A wrapped meal'),('Food','Mango','A tropical fruit'),('Food','Pretzel','A twisted baked snack'),('Food','Lasagna','A layered pasta dish'),('Food','Blueberry','A small dark berry'),('Food','Waffle','A gridded breakfast cake'),('Food','Avocado','A creamy green fruit'),('Food','Dumpling','A filled dough parcel'),('Food','Pineapple','A spiky tropical fruit'),('Food','Omelet','A folded egg dish'),('Food','Bagel','A ring-shaped bread'),('Food','Lemonade','A tart summer drink'),('Food','Cupcake','A small frosted cake'),('Food','Nachos','Chips with toppings'),('Food','Coconut','A hard-shelled fruit'),('Food','Ravioli','Pasta pockets with filling'),('Food','Pancetta','A cured pork ingredient'),('Food','Popsicle','A frozen treat on a stick'),('Food','Cranberry','A tart red berry'),('Food','Granola','A crunchy oat mix'),
('Animals','Meerkat','A small desert mammal'),('Animals','Peacock','A bird with a fan tail'),('Animals','Walrus','A tusked marine mammal'),('Animals','Chameleon','A color-changing reptile'),('Animals','Koala','A eucalyptus-eating marsupial'),('Animals','Falcon','A fast hunting bird'),('Animals','Lemur','A ring-tailed island primate'),('Animals','Badger','A burrowing mammal'),('Animals','Manatee','A gentle aquatic mammal'),('Animals','Cobra','A hooded snake'),('Animals','Sparrow','A small common bird'),('Animals','Salamander','An amphibian with a tail'),('Animals','Bison','A large shaggy grazer'),('Animals','Moth','An insect drawn to light'),('Animals','Lobster','A clawed sea animal'),('Animals','Alpaca','A woolly Andean animal'),('Animals','Raccoon','A masked nighttime forager'),('Animals','Pelican','A bird with a throat pouch'),('Animals','Gecko','A wall-climbing lizard'),('Animals','Donkey','A sturdy pack animal'),
('Places','Observatory','A place to study stars'),('Places','Aquarium','A home for water life'),('Places','Stadium','A venue for sports crowds'),('Places','Monastery','A quiet religious home'),('Places','Canyon','A deep rocky valley'),('Places','Greenhouse','A warm place for plants'),('Places','Harbor','A sheltered place for boats'),('Places','Bakery','A shop for fresh bread'),('Places','Courthouse','A building for legal matters'),('Places','Waterfall','A river drop over a ledge'),('Places','TrainStation','A stop for rail travel'),('Places','Playground','An outdoor place for children'),('Places','Cave','A natural underground space'),('Places','Vineyard','A farm for grapes'),('Places','Pyramid','An ancient triangular monument'),('Places','Planetarium','A theater for the night sky'),('Places','Market','A place with many vendors'),('Places','Island','Land surrounded by water'),('Places','Workshop','A place to make or repair'),('Places','Campground','A place to pitch a tent'),
('Objects','HourglassTimer','A glass timekeeper'),('Objects','Snowglobe','A miniature winter scene'),('Objects','Lantern','A portable source of light'),('Objects','Skateboard','A board with four wheels'),('Objects','Typewriter','A manual writing machine'),('Objects','Thermos','A container that keeps drinks hot'),('Objects','Binoculars','A tool for distant viewing'),('Objects','Candelabra','A holder for several candles'),('Objects','Suitcase','Luggage for a journey'),('Objects','Keychain','A ring for holding keys'),('Objects','Dumbbell','A small hand weight'),('Objects','Kaleidoscope','A tube of shifting patterns'),('Objects','Mailbox','A container for letters'),('Objects','Snowshovel','A tool for clearing snow'),('Objects','Sundial','A device that uses shadows'),('Objects','Headphones','Wearable personal speakers'),('Objects','Trophy','An award displayed on a shelf'),('Objects','Magnifier','A lens that makes things look larger'),('Objects','Lifebuoy','A floating rescue ring'),('Objects','Tripod','A three-legged camera stand'),
('Nature','Moonstone','A glowing-looking mineral'),('Nature','Wildfire','An uncontrolled forest blaze'),('Nature','Tornado','A violently rotating storm'),('Nature','Sequoia','A towering ancient tree'),('Nature','Tidepool','A small shore pool at low tide'),('Nature','Dewdrop','A bead of morning moisture'),('Nature','Meadow','An open grassy field'),('Nature','Aurora','Colorful lights near the poles'),('Nature','Stalactite','A cave formation hanging down'),('Nature','Boulder','A very large rock'),('Nature','Monsoon','A seasonal period of heavy rain'),('Nature','Coral','A reef-building sea animal'),('Nature','Fossil','A preserved trace of ancient life'),('Nature','Mangrove','A coastal salt-tolerant tree'),('Nature','Earthquake','Shaking caused underground'),('Nature','Mushroom','A fungus with a cap'),('Nature','Dandelion','A yellow flower with floating seeds'),('Nature','Creek','A small flowing stream'),('Nature','Hailstone','A ball of ice from a storm'),('Nature','Pollen','Fine plant dust carried by air'),
('Activities','Fencing','A sword-based sport'),('Activities','Pottery','Shaping clay into objects'),('Activities','Birdwatching','Observing birds outdoors'),('Activities','Juggling','Keeping objects moving in the air'),('Activities','Bouldering','Climbing short rock walls'),('Activities','Paddleboarding','Standing on a board on water'),('Activities','Gardening','Growing plants at home'),('Activities','Origami','Folding paper into shapes'),('Activities','Surfing','Riding ocean waves'),('Activities','Stargazing','Watching the night sky'),('Activities','Geocaching','Finding hidden items with coordinates'),('Activities','Calligraphy','Decorative handwriting'),('Activities','Snowboarding','Sliding downhill on a board'),('Activities','Jogging','Running at an easy pace'),('Activities','Woodworking','Making things from timber'),('Activities','Baking','Cooking dough with dry heat'),('Activities','Rowing','Moving a boat with oars'),('Activities','Meditation','Quiet focused breathing'),('Activities','Puppeteering','Performing with figures on strings'),('Activities','Foraging','Gathering wild edible plants')
on conflict(category,word) do nothing;
