export const MIN_PLAYERS = 4;
export const MAX_PLAYERS = 8;
export const MAX_IMPOSTERS = 2;

export function validateRoomSize(playerCount, imposterCount) {
  if (!Number.isInteger(playerCount) || playerCount < MIN_PLAYERS || playerCount > MAX_PLAYERS) {
    throw new Error('ROOM_SIZE_INVALID');
  }
  if (!Number.isInteger(imposterCount) || imposterCount < 1 || imposterCount > MAX_IMPOSTERS || imposterCount >= playerCount) {
    throw new Error('IMPOSTER_COUNT_INVALID');
  }
  return true;
}

export function normalizeClue(value, secretWord) {
  const clue = String(value ?? '').trim();
  if (!clue || clue.length > 30 || /\s/.test(clue) || /https?:\/\//i.test(clue)) throw new Error('CLUE_INVALID');
  if (clue.normalize('NFKC').toLocaleLowerCase() === String(secretWord).normalize('NFKC').toLocaleLowerCase()) {
    throw new Error('CLUE_REVEALS_WORD');
  }
  return clue;
}

export function scoreRound({ players, imposters, ballots, mode }) {
  const impostersSet = new Set(imposters);
  if (impostersSet.size === 0 || impostersSet.size >= players.length) throw new Error('IMPOSTER_COUNT_INVALID');
  const civilians = players.filter(id => !impostersSet.has(id));
  const hits = Object.fromEntries([...impostersSet].map(id => [id, 0]));
  for (const voter of civilians) {
    const picks = ballots[voter] ?? [];
    if (picks.length !== impostersSet.size || new Set(picks).size !== picks.length || picks.some(id => id === voter || !players.includes(id))) {
      throw new Error('BALLOT_INVALID');
    }
    for (const id of picks) if (impostersSet.has(id)) hits[id] += 1;
  }
  const caught = Object.fromEntries([...impostersSet].map(id => [id, hits[id] > civilians.length / 2]));
  const points = Object.fromEntries(players.map(id => [id, 0]));
  for (const id of impostersSet) {
    if (!caught[id]) points[id] = mode === 'deception' ? civilians.length - hits[id] : 1;
  }
  for (const id of civilians) {
    const correct = (ballots[id] ?? []).filter(pick => impostersSet.has(pick)).length;
    if (mode === 'team') points[id] = [...impostersSet].every(imposter => caught[imposter]) ? 1 : 0;
    else if (mode === 'partial' || mode === 'deception') points[id] = correct / impostersSet.size;
    else throw new Error('SCORING_MODE_INVALID');
  }
  return { points, caught, hits, fooled: Object.fromEntries([...impostersSet].map(id => [id, civilians.length - hits[id]])) };
}

export function shouldContinueClues(choices, playerCount) {
  return Object.values(choices).filter(choice => choice === 'more').length > playerCount / 2;
}
