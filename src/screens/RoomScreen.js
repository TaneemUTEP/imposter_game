import React, { useCallback, useEffect, useRef, useState } from 'react';
import { ScrollView, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';
import { palette } from '../theme/palette';
import { ActionButton } from '../components/ActionButton';
import { roomSnapshot, setReady, updateRoomSettings, startRound, privateRound, acknowledgeRole, submitClue, submitBallot, chooseContinuation, advanceContinuation, advanceReveal, finishMatch, maintainRoom, leaveRoom, supabase } from '../lib/supabase';

export function RoomScreen({ room, onLeave }) {
  const [snapshot, setSnapshot] = useState(null);
  const [me, setMe] = useState(null);
  const [secret, setSecret] = useState(null);
  const [clue, setClue] = useState('');
  const [selected, setSelected] = useState([]);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [matchTitles,setMatchTitles]=useState(null);
  const [rouletteIndex,setRouletteIndex]=useState(0);
  const loadedVoteRound=useRef(null);

  const refresh = useCallback(async () => {
    try {
      const state = await roomSnapshot(room.id);
      setSnapshot(state);
      if (state.round?.phase === 'voting' && loadedVoteRound.current !== state.round.id) {
        setSelected(state.round.my_vote || []);
        loadedVoteRound.current = state.round.id;
      }
      if (state.round?.phase === 'continue_vote' && state.round.deadline_at && Date.now() >= new Date(state.round.deadline_at).getTime()) {
        await advanceContinuation(state.round.id);
        const updated = await roomSnapshot(room.id);
        setSnapshot(updated);
      }
      if (state.round?.phase === 'reveal' && state.round.reveal_at && Date.now() - new Date(state.round.reveal_at).getTime() >= 4000) {
        await advanceReveal(state.round.id);
        const updated = await roomSnapshot(room.id);
        setSnapshot(updated);
      }
      const { data: { user } } = await supabase.auth.getUser();
      setMe(user?.id);
      const round = state.round;
      if (round) {
        const role = await privateRound(round.id);
        setSecret(role);
      } else setSecret(null);
    } catch (cause) { setError(cause.message || 'Could not refresh the room.'); }
  }, [room.id]);

  useEffect(() => {
    refresh();
    const timer = setInterval(()=>{maintainRoom(room.id).catch(()=>{});refresh();}, 10000);
    const channel = supabase.channel(`room-${room.id}`).on('postgres_changes', { event: '*', schema: 'public', table: 'room_members', filter: `room_id=eq.${room.id}` }, refresh).subscribe();
    return () => { clearInterval(timer); supabase.removeChannel(channel); };
  }, [room.id, refresh]);

  useEffect(()=>{
    if(snapshot?.round?.phase!=='reveal')return;
    const timer=setInterval(()=>setRouletteIndex(index=>(index+1)%Math.max(1,snapshot.members.length)),120);
    return()=>clearInterval(timer);
  },[snapshot?.round?.phase,snapshot?.members?.length]);

  async function act(operation) {
    setBusy(true); setError('');
    try { await operation(); await refresh(); }
    catch (cause) { setError(cause.message || 'That action did not go through.'); }
    finally { setBusy(false); }
  }

  if (!snapshot) return <View style={styles.center}><Text style={styles.heading}>Connecting to your room…</Text>{error ? <Text style={styles.error}>{error}</Text> : null}</View>;

  const members = snapshot.members || [];
  const round = snapshot.round;
  const myMember = members.find(member => member.id === me);
  const isHost = snapshot.host_id === me;
  const seats = [...members].sort((left,right)=>left.seat-right.seat);
  const startIndex = seats.findIndex(member=>member.id===round?.starting_user);
  const clueCount = round?.clues?.filter(item=>item.pass===round.clue_pass).length || 0;
  const activeCluePlayer = startIndex<0 ? null : seats[(startIndex+clueCount)%seats.length];

  return <ScrollView contentContainerStyle={styles.page}>
    <TouchableOpacity accessibilityRole="button" onPress={()=>act(async()=>{await leaveRoom(room.id);onLeave();})}><Text style={styles.back}>← Leave room</Text></TouchableOpacity>
    <View style={styles.header}><Text style={styles.eyebrow}>ROOM CODE</Text><Text selectable style={styles.code}>{snapshot.code}</Text><Text style={styles.sub}>Share this code with your friends</Text></View>
    {error ? <Text accessibilityRole="alert" style={styles.error}>{error}</Text> : null}
    {!round || ['results','aborted'].includes(round.phase) ? <View style={styles.card}><Text style={styles.heading}>Players · {members.length}/8</Text>{members.map(member => <View key={member.id} style={styles.member}><View style={styles.dot}><Text>{member.name.slice(0,1).toUpperCase()}</Text></View><Text style={styles.memberName}>{member.name}{member.id === me ? ' (you)' : ''}{member.id === snapshot.host_id ? ' · host' : ''}</Text><Text style={styles.ready}>{member.ready ? 'Ready' : 'Not ready'}</Text></View>)}
      {isHost ? <View style={styles.settings}><Text style={styles.settingLabel}>SCORING</Text><View style={styles.actions}>{['team','partial','deception'].map(mode => <TouchableOpacity key={mode} accessibilityRole="radio" accessibilityState={{ selected: snapshot.scoring_mode === mode }} onPress={() => act(() => updateRoomSettings(room.id,mode,snapshot.imposter_count))} style={[styles.settingOption,snapshot.scoring_mode===mode && styles.selected]}><Text style={styles.optionText}>{mode}</Text></TouchableOpacity>)}</View><Text style={styles.settingLabel}>IMPOSTERS</Text><View style={styles.actions}>{[1,2].filter(count => count < members.length).map(count => <TouchableOpacity key={count} accessibilityRole="radio" accessibilityState={{ selected: snapshot.imposter_count === count }} onPress={() => act(() => updateRoomSettings(room.id,snapshot.scoring_mode,count))} style={[styles.settingOption,snapshot.imposter_count===count && styles.selected]}><Text style={styles.optionText}>{count}</Text></TouchableOpacity>)}</View></View> : <Text style={styles.wait}>Mode: {snapshot.scoring_mode} · Imposters: {snapshot.imposter_count}</Text>}
      <ActionButton label={myMember?.ready ? '✓ You’re ready' : 'I’m ready'} color={palette.mint} onPress={() => act(() => setReady(room.id, !myMember?.ready))} disabled={busy} />
      {isHost ? <View style={{ marginTop: 12 }}><ActionButton label={members.length < 4 ? `Need ${4-members.length} more players` : 'Start round'} color={palette.coral} onPress={() => act(() => startRound(room.id))} disabled={busy || members.length < 4 || members.some(member => !member.ready)} /></View> : <Text style={styles.wait}>The host can start when 4–8 players are ready.</Text>}
    </View> : <View style={styles.card}>
      <Text style={styles.eyebrow}>ROUND {round.round_number} · PASS {round.clue_pass}</Text>
      {round.phase === 'roles' ? <><Text style={styles.heading}>Your secret card</Text><Text style={styles.secret}>{secret?.is_imposter ? 'IMPOSTER' : (secret?.word || 'Loading…')}</Text><Text style={styles.sub}>{secret?.is_imposter ? `Hint: ${secret.hint}` : 'Keep your word secret. Give one related word when it is your turn.'}</Text><ActionButton label="I’ve seen my role" color={palette.coral} onPress={() => act(async () => { await acknowledgeRole(round.id); })} disabled={busy} /></> : null}
      {round.clues?.length ? <View style={styles.clueList}><Text style={styles.eyebrow}>CLUES SO FAR</Text>{round.clues.map((item,index) => <Text key={`${item.pass}-${index}`} style={styles.clueLine}>Pass {item.pass} · {item.player_name}: <Text style={styles.clueWord}>{item.text}</Text></Text>)}</View> : null}
      {round.phase === 'clues' ? <><Text style={styles.heading}>Clue pass</Text><Text style={styles.sub}>One word per player, in order.</Text><View style={styles.turnNotice}><Text style={styles.turnLabel}>UP NEXT</Text><Text style={styles.turnName}>{activeCluePlayer?.name || 'Waiting for players'}</Text></View><TextInput accessibilityLabel="Your one-word clue" value={clue} onChangeText={setClue} placeholder="Your clue" style={styles.input} maxLength={30} /><ActionButton label={activeCluePlayer?.id===me?'Submit clue':`Waiting for ${activeCluePlayer?.name||'player'}`} color={palette.coral} onPress={() => act(async () => { await submitClue(round.id, clue, round.version); setClue(''); })} disabled={busy || !clue.trim() || activeCluePlayer?.id!==me} /></> : null}
      {round.phase === 'voting' ? <><Text style={styles.heading}>Who are the imposters?</Text><Text style={styles.sub}>Choose {snapshot.imposter_count} player{snapshot.imposter_count === 1 ? '' : 's'}. Votes submitted: {round.submitted_votes}/{members.length}</Text>{members.filter(member => member.id !== me).map(member => <TouchableOpacity key={member.id} accessibilityRole="checkbox" accessibilityState={{ checked: selected.includes(member.id) }} onPress={() => setSelected(items => items.includes(member.id) ? items.filter(id => id !== member.id) : items.length < snapshot.imposter_count ? [...items, member.id] : items)} style={[styles.member, selected.includes(member.id) && styles.selected]}><Text style={styles.memberName}>{selected.includes(member.id) ? '☑ ' : '☐ '}{member.name}</Text></TouchableOpacity>)}<ActionButton label="Submit or change vote" color={palette.coral} onPress={() => act(() => submitBallot(round.id, selected, round.version))} disabled={busy || selected.length !== snapshot.imposter_count} /></> : null}
      {round.phase === 'continue_vote' ? <><Text style={styles.heading}>Want another clue pass?</Text><Text style={styles.sub}>A majority can ask for one more pass before the reveal.</Text><View style={styles.actions}><ActionButton label="More clues" color={palette.mint} onPress={() => act(() => chooseContinuation(round.id,'more',round.version))} disabled={busy} /><ActionButton label="Reveal" color={palette.coral} onPress={() => act(() => chooseContinuation(round.id,'reveal',round.version))} disabled={busy} /></View></> : null}
      {round.phase === 'reveal' ? <><Text style={styles.heading}>🎡 The reveal</Text><View style={styles.roulette}><Text style={styles.rouletteName}>{members[rouletteIndex]?.name||'…'}</Text></View><Text style={styles.sub}>The votes are locked. The wheel is slowing down…</Text></> : null}
      {round.phase === 'results' ? <><Text style={styles.heading}>Round results</Text><Text style={styles.sub}>The secret word was <Text style={styles.clueWord}>{round.word}</Text>.</Text>{round.results?.map(result => <View key={result.player_id} style={styles.resultLine}><Text style={styles.memberName}>{result.name}{result.is_imposter ? ' · IMPOSTER' : ''}</Text><Text style={styles.resultScore}>{result.points} pts</Text>{result.is_imposter ? <Text style={styles.ready}>{result.caught ? `Caught · ${result.hits} civilian votes` : `Escaped · fooled ${result.fooled}`}</Text> : null}<Text style={styles.ready}>Voted for: {result.votes?.map(vote=>vote.name).join(', ')||'—'}</Text></View>)}</> : null}
      {round.phase === 'results' && isHost ? <View style={{marginTop:14}}><ActionButton label="Finish match and reveal titles" color={palette.ink} onPress={()=>act(async()=>setMatchTitles(await finishMatch(round.match_id)))} disabled={busy}/></View>:null}
      {matchTitles ? <View style={styles.clueList}><Text style={styles.eyebrow}>MATCH TITLES</Text>{matchTitles.map((item,index)=><Text key={`${item.title}-${index}`} style={styles.clueLine}>{item.name}: {item.title}</Text>)}</View>:null}
      <ActionButton label="Refresh game state" color={palette.ink} secondary onPress={refresh} />
    </View>}
  </ScrollView>;
}

const styles = StyleSheet.create({ page: { width:'100%',maxWidth:680,alignSelf:'center',padding:24,paddingBottom:50 }, center:{flex:1,justifyContent:'center',alignItems:'center',padding:24}, back:{color:palette.muted,fontWeight:'700',paddingVertical:12}, header:{alignItems:'center',paddingVertical:25},eyebrow:{color:palette.muted,fontSize:11,fontWeight:'900',letterSpacing:1.5},code:{color:palette.ink,fontSize:42,fontWeight:'900',letterSpacing:8,marginTop:5},sub:{color:palette.muted,fontSize:14,lineHeight:21,marginTop:8,marginBottom:18},card:{backgroundColor:'#fff',borderColor:palette.line,borderWidth:1,borderRadius:20,padding:20},heading:{fontSize:22,fontWeight:'900',color:palette.ink,marginBottom:14},member:{minHeight:52,flexDirection:'row',alignItems:'center',borderBottomWidth:1,borderColor:palette.line,gap:10},dot:{width:32,height:32,borderRadius:16,backgroundColor:palette.lilac,alignItems:'center',justifyContent:'center'},memberName:{flex:1,color:palette.ink,fontWeight:'700'},ready:{color:palette.muted,fontSize:11},wait:{textAlign:'center',color:palette.muted,marginTop:14},error:{color:'#AA4036',backgroundColor:'#FCE7E4',padding:12,borderRadius:10,marginBottom:12},secret:{fontSize:28,fontWeight:'900',color:palette.coral,marginVertical:18},input:{borderWidth:1,borderColor:palette.line,borderRadius:12,padding:14,marginVertical:12,fontSize:16,color:palette.ink},selected:{backgroundColor:'#FFF2E8',borderColor:palette.coral},actions:{flexDirection:'row',flexWrap:'wrap',gap:8,marginBottom:12},settings:{marginVertical:15},settingLabel:{color:palette.muted,fontSize:10,fontWeight:'900',letterSpacing:1,marginBottom:7},settingOption:{borderWidth:1,borderColor:palette.line,borderRadius:9,paddingVertical:9,paddingHorizontal:12},optionText:{color:palette.ink,fontWeight:'700',textTransform:'capitalize'},clueList:{padding:12,backgroundColor:'#FFF8EB',borderRadius:12,marginBottom:18},clueLine:{color:palette.muted,fontSize:13,marginTop:7},clueWord:{color:palette.ink,fontWeight:'900'},turnNotice:{borderRadius:12,padding:14,backgroundColor:'#EAF7F0',marginBottom:10},turnLabel:{color:palette.muted,fontSize:10,fontWeight:'900',letterSpacing:1},turnName:{color:palette.ink,fontSize:18,fontWeight:'900',marginTop:4},resultLine:{paddingVertical:10,borderBottomWidth:1,borderColor:palette.line},resultScore:{color:palette.coral,fontWeight:'900'},roulette:{height:110,borderRadius:20,backgroundColor:'#FFF2D9',alignItems:'center',justifyContent:'center',marginBottom:12,borderWidth:2,borderColor:palette.yellow},rouletteName:{fontSize:28,fontWeight:'900',color:palette.ink},resultTitle:{fontWeight:'900'}});
