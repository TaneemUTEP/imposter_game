const SCORING_MODES = new Set(['team', 'partial', 'deception']);

/** Reference scorer for client presentation and rules tests. Database results remain authoritative. */
function calculateRoundResults({ players, imposters, ballots, mode }) {
  if (!Array.isArray(players) || players.length < 4 || players.length > 8) throw new Error('ROOM_SIZE_INVALID');
  if (!Array.isArray(imposters) || imposters.length < 1 || imposters.length > 2 || imposters.length >= players.length) {
    throw new Error('IMPOSTER_COUNT_INVALID');
  }
  if (!SCORING_MODES.has(mode)) throw new Error('SCORING_MODE_INVALID');

  const playerIds = new Set(players);
  const imposterIds = new Set(imposters);
  if (playerIds.size !== players.length || imposterIds.size !== imposters.length ||
      imposters.some(id => !playerIds.has(id))) throw new Error('ROUND_ROSTER_INVALID');
  if (!Array.isArray(ballots) || ballots.length !== players.length) throw new Error('BALLOT_INVALID');

  const ballotsByVoter = new Map();
  const hits = new Map(imposters.map(id => [id, 0]));
  for (const ballot of ballots) {
    if (!playerIds.has(ballot.voterId) || ballotsByVoter.has(ballot.voterId) ||
        !Array.isArray(ballot.suspects) || ballot.suspects.length !== imposters.length ||
        new Set(ballot.suspects).size !== imposters.length || ballot.suspects.includes(ballot.voterId) ||
        ballot.suspects.some(id => !playerIds.has(id))) throw new Error('BALLOT_INVALID');
    ballotsByVoter.set(ballot.voterId, ballot.suspects);
    if (!imposterIds.has(ballot.voterId)) {
      for (const suspectId of ballot.suspects) {
        if (imposterIds.has(suspectId)) hits.set(suspectId, hits.get(suspectId) + 1);
      }
    }
  }

  const civilians = players.length - imposters.length;
  const caught = new Map(imposters.map(id => [id, hits.get(id) > civilians / 2]));
  const everyImposterCaught = imposters.every(id => caught.get(id));
  const results = {};

  for (const playerId of players) {
    const isImposter = imposterIds.has(playerId);
    const playerHits = isImposter ? hits.get(playerId) : 0;
    const fooled = isImposter ? civilians - playerHits : 0;
    const correct = isImposter ? 0 : ballotsByVoter.get(playerId).filter(id => imposterIds.has(id)).length;
    let points = 0;

    if (isImposter) {
      if (!caught.get(playerId)) points = mode === 'deception' ? fooled : 1;
    } else if (mode === 'team') {
      points = everyImposterCaught ? 1 : 0;
    } else {
      points = correct / imposters.length;
    }

    results[playerId] = {
      isImposter,
      caught: isImposter ? caught.get(playerId) : null,
      hits: playerHits,
      fooled,
      correct,
      pointsHalfUnits: Math.round(points * 2),
    };
  }
  return results;
}

module.exports = { calculateRoundResults };
