import { createClient } from '@supabase/supabase-js';
import AsyncStorage from '@react-native-async-storage/async-storage';

/**
 * Shared Supabase client. It stays null until the public project URL and anon
 * key are present, allowing screens to show a setup message instead of crashing.
 * Never place a service-role key in this client bundle.
 */
const url = process.env.EXPO_PUBLIC_SUPABASE_URL;
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

export const supabase = url && anonKey ? createClient(url, anonKey, {
  auth: { storage: AsyncStorage, autoRefreshToken: true, persistSession: true, detectSessionInUrl: true },
}) : null;

/** Create an email identity; Supabase may return without a session until email confirmation. */
export async function createEmailAccount(email, password, displayName) {
  if (!supabase) throw new Error('BACKEND_NOT_CONFIGURED');
  const emailRedirectTo = typeof window !== 'undefined' ? window.location.origin : undefined;
  const { data, error } = await supabase.auth.signUp({
    email: email.trim(), password,
    options: { data: { display_name: displayName.trim() }, emailRedirectTo },
  });
  if (error) throw error;
  return data;
}

/** Sign into an existing email account. */
export async function signInWithEmail(email, password) {
  if (!supabase) throw new Error('BACKEND_NOT_CONFIGURED');
  const { data, error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
  if (error) throw error;
  return data;
}

/** Return the current identity or create a Supabase anonymous guest identity. */
export async function ensureGuestSession() {
  if (!supabase) throw new Error('BACKEND_NOT_CONFIGURED');
  const { data: { session }, error: sessionError } = await supabase.auth.getSession();
  if (sessionError) throw sessionError;
  if (session) return session.user;
  const { data, error } = await supabase.auth.signInAnonymously();
  if (error) throw error;
  return data.user;
}

/**
 * Create a room through the database RPC. A persisted command UUID is reused
 * after a lost response so a retry can return the original room instead of
 * creating a duplicate.
 */
export async function createRoom(displayName) {
  await ensureGuestSession();
  const commandKey = 'pending-room-create-command';
  let commandId = await AsyncStorage.getItem(commandKey);
  if (!commandId) {
    commandId = globalThis.crypto?.randomUUID?.() || 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
      const r = Math.random() * 16 | 0;
      return (c === 'x' ? r : (r & 3 | 8)).toString(16);
    });
    await AsyncStorage.setItem(commandKey, commandId);
  }
  const { data, error } = await supabase.rpc('create_room', { p_display_name: displayName.trim(), p_command_id: commandId });
  if (error) throw error;
  await AsyncStorage.removeItem(commandKey);
  return data;
}

/** Join by normalized room code; the RPC may return `waiting: true` for a queue seat. */
export async function joinRoom(code, displayName) {
  await ensureGuestSession();
  const { data, error } = await supabase.rpc('join_room', { p_code: code.trim().toUpperCase(), p_display_name: displayName.trim() });
  if (error) throw error;
  return data;
}

/** Read the membership-authorized public snapshot; role secrets use privateRound(). */
export async function roomSnapshot(roomId) {
  const { data, error } = await supabase.rpc('get_room_snapshot', { p_room: roomId });
  if (error) throw error;
  return data;
}

/** Set readiness for either a seated member or a waitlisted player. */
export async function setReady(roomId, ready) {
  const { error } = await supabase.rpc('set_ready', { p_room: roomId, p_ready: ready });
  if (error) throw error;
}

/** Change host-configurable scoring, imposter count, and word categories in lobby. */
export async function updateRoomSettings(roomId, mode, imposters, categories) {
  const { error } = await supabase.rpc('update_room_settings', { p_room: roomId, p_mode: mode, p_imposters: imposters, p_categories: categories });
  if (error) throw error;
}

/** Ask the server to create the next round, snapshot its roster, and assign roles. */
export async function startRound(roomId) {
  const { data, error } = await supabase.rpc('start_round', { p_room: roomId });
  if (error) throw error;
  return data;
}

/** Retrieve only the current user's permitted role/word/hint fields. */
export async function privateRound(roundId) {
  const { data, error } = await supabase.rpc('get_private_round', { p_round: roundId });
  if (error) throw error;
  return data;
}

/** Acknowledge viewing the private role card so the server can open clue entry. */
export async function acknowledgeRole(roundId) {
  const { data, error } = await supabase.rpc('acknowledge_role', { p_round: roundId });
  if (error) throw error;
  return data;
}

/** Submit the caller's clue for the active seat and clue pass. */
export async function submitClue(roundId, clue, version) {
  const { data, error } = await supabase.rpc('submit_clue', { p_round: roundId, p_clue: clue, p_version: version });
  if (error) throw error;
  return data;
}

/** Submit or replace the caller's suspect ballot until the server locks voting. */
export async function submitBallot(roundId, suspects, version) {
  const { data, error } = await supabase.rpc('submit_ballot', { p_round: roundId, p_suspects: suspects, p_version: version });
  if (error) throw error;
  return data;
}

/** Save/edit a More clues or Reveal choice until the shared deadline. */
export async function chooseContinuation(roundId, choice, version) {
  const { data, error } = await supabase.rpc('choose_more_clues', { p_round: roundId, p_choice: choice, p_version: version });
  if (error) throw error;
  return data;
}

/** Advance the roulette after its server-timed reveal duration. */
export async function advanceReveal(roundId) {
  const { error } = await supabase.rpc('advance_reveal', { p_round: roundId });
  if (error) throw error;
}

/** End the active match, persist eligible titles, and return them for display. */
export async function finishMatch(matchId) {
  const { data, error } = await supabase.rpc('finish_match', { p_match: matchId });
  if (error) throw error;
  return data;
}

/** Refresh the caller's room heartbeat and reconcile stale presence/host state. */
export async function maintainRoom(roomId) {
  const { error } = await supabase.rpc('heartbeat_room', { p_room: roomId });
  if (error) throw error;
  const { error: reconcileError } = await supabase.rpc('reconcile_room', { p_room: roomId });
  if (reconcileError) throw reconcileError;
}

/** Leave the room/queue; an unfinished round is aborted by the database policy. */
export async function leaveRoom(roomId) {
  const { error } = await supabase.rpc('leave_room', { p_room: roomId });
  if (error) throw error;
}

/** Resolve the shared continuation deadline; repeated calls are safe. */
export async function advanceContinuation(roundId) {
  const { data, error } = await supabase.rpc('advance_continuation', { p_round: roundId });
  if (error) throw error;
  return data;
}
