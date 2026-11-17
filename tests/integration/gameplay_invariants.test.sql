begin;
select plan(8);

select has_table('public','room_waitlist','active-round arrivals have a waitlist');
select has_column('public','room_waitlist','ready','queued players can ready for promotion');
select has_column('public','matches','word_categories','match categories are frozen');
select has_column('public','round_roles','seat','round seating is snapshotted');
select ok((select count(*) >= 150 from public.word_pairs),'at least 150 word pairs are seeded');
select is((select count(distinct category)::integer from public.word_pairs),6,'all six categories are represented');
select is((select count(*)::integer from public.word_pairs),
          (select count(distinct public.normalize_game_word(word))::integer from public.word_pairs),
          'normalized secret words are unique');
select is((select count(*)::integer from public.word_pairs where position(public.normalize_game_word(word) in public.normalize_game_word(hint))>0),0,
          'hints do not contain their answer');

select * from finish();
rollback;
