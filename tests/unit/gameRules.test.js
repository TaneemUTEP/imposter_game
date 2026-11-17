const { test } = require('node:test');
const assert = require('node:assert/strict');
const { calculateRoundResults } = require('../../src/lib/gameRules');

const players = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
const imposters = ['A', 'B'];
const ballots = [
  { voterId: 'A', suspects: ['B', 'C'] },
  { voterId: 'B', suspects: ['A', 'D'] },
  { voterId: 'C', suspects: ['A', 'B'] },
  { voterId: 'D', suspects: ['A', 'C'] },
  { voterId: 'E', suspects: ['A', 'D'] },
  { voterId: 'F', suspects: ['A', 'E'] },
  { voterId: 'G', suspects: ['B', 'F'] },
  { voterId: 'H', suspects: ['C', 'D'] },
];

test('team mode awards civilians only when every imposter is caught by civilian votes', () => {
  const results = calculateRoundResults({ players, imposters, ballots, mode: 'team' });

  assert.equal(results.A.hits, 4);
  assert.equal(results.A.caught, true);
  assert.equal(results.A.pointsHalfUnits, 0);
  assert.equal(results.B.hits, 2);
  assert.equal(results.B.caught, false);
  assert.equal(results.B.fooled, 4);
  assert.equal(results.B.pointsHalfUnits, 2);
  assert.deepEqual(players.slice(2).map(id => results[id].pointsHalfUnits), [0, 0, 0, 0, 0, 0]);
});

test('partial mode gives civilians half-point increments and escaping imposters one point', () => {
  const results = calculateRoundResults({ players, imposters, ballots, mode: 'partial' });

  assert.deepEqual(players.slice(2).map(id => results[id].pointsHalfUnits), [2, 1, 1, 1, 1, 0]);
  assert.equal(results.A.pointsHalfUnits, 0);
  assert.equal(results.B.pointsHalfUnits, 2);
});

test('deception mode awards an escaping imposter one point per civilian fooled', () => {
  const results = calculateRoundResults({ players, imposters, ballots, mode: 'deception' });

  assert.equal(results.A.pointsHalfUnits, 0);
  assert.equal(results.B.pointsHalfUnits, 8);
  assert.deepEqual(players.slice(2).map(id => results[id].pointsHalfUnits), [2, 1, 1, 1, 1, 0]);
});

test('a strict majority catches an imposter; a tie favors the imposter', () => {
  const players = ['A', 'B', 'C', 'D', 'E', 'F', 'G'];
  const tiedVotes = [
    { voterId: 'A', suspects: ['B'] },
    { voterId: 'B', suspects: ['A'] },
    { voterId: 'C', suspects: ['D'] },
    { voterId: 'D', suspects: ['A'] },
    { voterId: 'E', suspects: ['B'] },
    { voterId: 'F', suspects: ['A'] },
    { voterId: 'G', suspects: ['B'] },
  ];
  const tied = calculateRoundResults({ players, imposters: ['A'], ballots: tiedVotes, mode: 'team' });
  assert.equal(tied.A.hits, 3);
  assert.equal(tied.A.caught, false);

  const majority = calculateRoundResults({
    players,
    imposters: ['A'],
    ballots: tiedVotes.map(ballot => ballot.voterId === 'G' ? { ...ballot, suspects: ['A'] } : ballot),
    mode: 'team',
  });
  assert.equal(majority.A.hits, 4);
  assert.equal(majority.A.caught, true);
});

test('a four-player single-imposter round awards only correct team members', () => {
  const result = calculateRoundResults({
    players: ['H','I','J','K'], imposters: ['K'], mode: 'team',
    ballots: [
      { voterId: 'H', suspects: ['K'] },
      { voterId: 'I', suspects: ['K'] },
      { voterId: 'J', suspects: ['K'] },
      { voterId: 'K', suspects: ['H'] },
    ],
  });
  assert.deepEqual(['H','I','J'].map(id => result[id].pointsHalfUnits), [2,2,2]);
  assert.equal(result.K.caught, true);
  assert.equal(result.K.pointsHalfUnits, 0);
});

test('rejects invalid rosters, duplicate voters, and self-votes', () => {
  assert.throws(() => calculateRoundResults({ players: ['A','B','C'], imposters: ['C'], ballots: [], mode: 'team' }), /ROOM_SIZE_INVALID/);
  assert.throws(() => calculateRoundResults({ players: ['A','B','C','D'], imposters: ['D'], mode: 'team', ballots: [
    { voterId: 'A', suspects: ['D'] }, { voterId: 'A', suspects: ['C'] },
    { voterId: 'B', suspects: ['D'] }, { voterId: 'C', suspects: ['D'] },
  ] }), /BALLOT_INVALID/);
});
