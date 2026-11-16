import { createClient } from '@supabase/supabase-js';

const url = process.env.EXPO_PUBLIC_SUPABASE_URL;
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

export const supabase = url && anonKey ? createClient(url, anonKey) : null;

export async function ensureGuestSession() {
  if (!supabase) throw new Error('BACKEND_NOT_CONFIGURED');
  const { data: { session }, error: sessionError } = await supabase.auth.getSession();
  if (sessionError) throw sessionError;
  if (session) return session.user;
  const { data, error } = await supabase.auth.signInAnonymously();
  if (error) throw error;
  return data.user;
}

export async function createRoom(displayName) {
  await ensureGuestSession();
  const { data, error } = await supabase.rpc('create_room', { p_display_name: displayName.trim() });
  if (error) throw error;
  return data;
}

export async function joinRoom(code, displayName) {
  await ensureGuestSession();
  const { data, error } = await supabase.rpc('join_room', { p_code: code.trim().toUpperCase(), p_display_name: displayName.trim() });
  if (error) throw error;
  return data;
}

export async function roomSnapshot(roomId) {
  const { data, error } = await supabase.rpc('get_room_snapshot', { p_room: roomId });
  if (error) throw error;
  return data;
}

export async function setReady(roomId, ready) {
  const { error } = await supabase.rpc('set_ready', { p_room: roomId, p_ready: ready });
  if (error) throw error;
}

export async function updateRoomSettings(roomId, mode, imposters) {
  const { error } = await supabase.rpc('update_room_settings', { p_room: roomId, p_mode: mode, p_imposters: imposters });
  if (error) throw error;
}

export async function startRound(roomId) {
  const { data, error } = await supabase.rpc('start_round', { p_room: roomId });
  if (error) throw error;
  return data;
}

export async function privateRound(roundId) {
  const { data, error } = await supabase.rpc('get_private_round', { p_round: roundId });
  if (error) throw error;
  return data;
}

export async function acknowledgeRole(roundId) {
  const { data, error } = await supabase.rpc('acknowledge_role', { p_round: roundId });
  if (error) throw error;
  return data;
}

export async function submitClue(roundId, clue, version) {
  const { data, error } = await supabase.rpc('submit_clue', { p_round: roundId, p_clue: clue, p_version: version });
  if (error) throw error;
  return data;
}

export async function submitBallot(roundId, suspects, version) {
  const { data, error } = await supabase.rpc('submit_ballot', { p_round: roundId, p_suspects: suspects, p_version: version });
  if (error) throw error;
  return data;
}

export async function chooseContinuation(roundId, choice, version) {
  const { data, error } = await supabase.rpc('choose_more_clues', { p_round: roundId, p_choice: choice, p_version: version });
  if (error) throw error;
  return data;
}

export async function advanceReveal(roundId) {
  const { error } = await supabase.rpc('advance_reveal', { p_round: roundId });
  if (error) throw error;
}

export async function finishMatch(matchId) {
  const { data, error } = await supabase.rpc('finish_match', { p_match: matchId });
  if (error) throw error;
  return data;
}

export async function maintainRoom(roomId) {
  const { error } = await supabase.rpc('heartbeat_room', { p_room: roomId });
  if (error) throw error;
  const { error: reconcileError } = await supabase.rpc('reconcile_room', { p_room: roomId });
  if (reconcileError) throw reconcileError;
}

export async function leaveRoom(roomId) {
  const { error } = await supabase.rpc('leave_room', { p_room: roomId });
  if (error) throw error;
}

export async function advanceContinuation(roundId) {
  const { data, error } = await supabase.rpc('advance_continuation', { p_round: roundId });
  if (error) throw error;
  return data;
}
