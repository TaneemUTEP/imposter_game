import React, { useEffect, useState } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { SafeAreaView, ScrollView, StatusBar, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';
import { ActionButton } from './src/components/ActionButton';
import { Avatar } from './src/components/Avatar';
import { TextField } from './src/components/TextField';
import { ThemeProvider, useTheme } from './src/theme/ThemeContext';
import { ThemeToggle } from './src/components/ThemeToggle';
import { getAuthErrorMessage } from './src/lib/authErrors';
import { createRoom as createOnlineRoom, joinRoom as joinOnlineRoom } from './src/lib/supabase';
import { RoomScreen } from './src/screens/RoomScreen';
import { ProfileScreen } from './src/screens/ProfileScreen';

const NAME_KEY = 'imposter.player-name';

/** Root composition: provides theme state to the landing, room, and profile views. */
export default function App() {
  return <ThemeProvider><AppContent /></ThemeProvider>;
}

/**
 * Small screen coordinator for the app's top-level flow.
 * Room/game state lives in RoomScreen; this component only switches between
 * the landing page, account/profile page, and the currently joined room.
 */
function AppContent() {
  const { palette, mode } = useTheme();
  const styles = makeStyles(palette);
  const [name, setName] = useState('');
  const [code, setCode] = useState('');
  const [message, setMessage] = useState('');
  const [room, setRoom] = useState(null);
  const [busy, setBusy] = useState(false);
  const [showProfile,setShowProfile]=useState(false);

  useEffect(() => {
    AsyncStorage.getItem(NAME_KEY).then(savedName => {
      if (savedName) setName(savedName);
    }).catch(() => {});
  }, []);

  /** Keep the chosen display name available on this device between launches. */
  function updateName(value) {
    setName(value);
    AsyncStorage.setItem(NAME_KEY, value).catch(() => {});
  }

  /** Return from account setup and adopt the account's display name locally. */
  function useAccountName(accountName) {
    if (accountName) updateName(accountName);
    setShowProfile(false);
    setMessage('You’re signed in. Your name will be used when you create or join a room.');
  }

  /** Create a backend room and route into its live lobby. */
  async function createRoom() {
    if (!name.trim()) return setMessage('Add your name first so friends know who opened the room.');
    setBusy(true);
    try { const created = await createOnlineRoom(name); setRoom({ id: created.room_id, code: created.code }); setMessage('Room created. Share the code with your friends.'); }
    catch (error) { setMessage(getAuthErrorMessage(error)); }
    finally { setBusy(false); }
  }

  /** Validate the six-character input before asking Supabase to join the room. */
  async function joinRoom() {
    if (!name.trim()) return setMessage('Add your name before joining.');
    if (code.trim().length !== 6) return setMessage('Enter the six-character room code.');
    setBusy(true);
    try { const joined = await joinOnlineRoom(code, name); setRoom({ id: joined.room_id, code: joined.code }); setMessage('You joined the room.'); }
    catch (error) { setMessage(getAuthErrorMessage(error)); }
    finally { setBusy(false); }
  }

  if(showProfile)return <SafeAreaView style={styles.safe}><StatusBar barStyle={mode === 'dark' ? 'light-content' : 'dark-content'} backgroundColor={palette.paper}/><ProfileScreen initialName={name} onAccountReady={useAccountName} onClose={()=>setShowProfile(false)}/></SafeAreaView>;
  if (room) return <SafeAreaView style={styles.safe}><StatusBar barStyle={mode === 'dark' ? 'light-content' : 'dark-content'} backgroundColor={palette.paper} /><RoomScreen room={room} onLeave={() => setRoom(null)} /></SafeAreaView>;

  return <SafeAreaView style={styles.safe}><StatusBar barStyle={mode === 'dark' ? 'light-content' : 'dark-content'} backgroundColor={palette.paper} /><ScrollView contentContainerStyle={styles.page}>
    <View style={styles.topbar}><View style={styles.brandMark}><Text style={styles.brandEmoji}>🕵️</Text></View><Text style={styles.brand}>WHO'S THE IMPOSTER?</Text><ThemeToggle /><TouchableOpacity accessibilityRole="button" onPress={()=>setShowProfile(true)} style={styles.profileButton}><Avatar size={30} /><Text style={styles.profileButtonText}>Account</Text></TouchableOpacity></View>
    <View style={styles.hero}><View style={styles.heroTag}><Text style={styles.heroTagText}>A LITTLE BLUFF GOES A LONG WAY</Text></View><Text style={styles.title}>One word.{ '\n' }One secret.{ '\n' }Who’s faking it?</Text><Text style={styles.subtitle}>Everyone gets the same secret word. Well… almost everyone.</Text>
      <View style={styles.scene}><View style={[styles.person, styles.personOne]}><Text style={styles.personFace}>😎</Text></View><View style={[styles.person, styles.personTwo]}><Text style={styles.personFace}>🤔</Text></View><View style={[styles.person, styles.personThree]}><Text style={styles.personFace}>😈</Text></View><View style={[styles.person, styles.personFour]}><Text style={styles.personFace}>🧐</Text></View><View style={styles.secretCard}><Text style={styles.secretLabel}>THE SECRET WORD</Text><Text style={styles.secretWord}>?????</Text><Text style={styles.secretHint}>One of you doesn’t know it</Text></View><View style={styles.sparkle}><Text>✦</Text></View><View style={styles.sparkleTwo}><Text>✳</Text></View></View>
    </View>
    <View style={styles.panel}><Text style={styles.panelTitle}>Ready to play?</Text><Text style={styles.panelSub}>No account needed to play as a guest. Choose the name your friends will see.</Text><TextInput accessibilityLabel="Your name" placeholder="Your name" placeholderTextColor={palette.muted} value={name} onChangeText={updateName} maxLength={24} style={styles.input} returnKeyType="next" />
      <ActionButton label={busy ? 'Connecting…' : 'Create a room  →'} color={palette.coral} onPress={createRoom} disabled={busy} /><View style={styles.divider}><View style={styles.rule} /><Text style={styles.or}>OR JOIN A GAME</Text><View style={styles.rule} /></View><View style={styles.joinRow}><TextField accessibilityLabel="Six-character room code" placeholder="ROOM CODE" value={code} onChangeText={value => setCode(value.replace(/[^a-z0-9]/gi, '').toUpperCase().slice(0, 6))} autoCapitalize="characters" maxLength={6} style={[styles.input, styles.codeInput]} /><TouchableOpacity accessibilityRole="button" disabled={busy} onPress={joinRoom} style={styles.joinButton}><Text style={styles.joinText}>{busy ? '…' : 'Join'}</Text></TouchableOpacity></View><TouchableOpacity accessibilityRole="button" onPress={()=>setShowProfile(true)}><Text style={styles.accountLink}>Have an account or want to save your stats? Account options</Text></TouchableOpacity>{message ? <Text accessibilityRole="alert" style={styles.message}>{message}</Text> : null}{room ? <View style={styles.roomNotice}><Text style={styles.roomNoticeTitle}>ROOM {room.code}</Text><Text style={styles.roomNoticeText}>The live lobby screen is the next game slice.</Text></View> : null}</View>
    <View style={styles.how}><Text style={styles.sectionTitle}>The game is simple. The bluffing isn’t.</Text><View style={styles.steps}><View style={styles.step}><View style={[styles.stepIcon, { backgroundColor: palette.yellow }]}><Text>🗝️</Text></View><Text style={styles.stepTitle}>Get your word</Text><Text style={styles.stepCopy}>Everyone sees the secret. The imposter gets a hint.</Text></View><View style={styles.step}><View style={[styles.stepIcon, { backgroundColor: palette.mint }]}><Text>💬</Text></View><Text style={styles.stepTitle}>Drop a clue</Text><Text style={styles.stepCopy}>Take turns sharing one word. Sound convincing.</Text></View><View style={styles.step}><View style={[styles.stepIcon, { backgroundColor: palette.lilac }]}><Text>🎯</Text></View><Text style={styles.stepTitle}>Find the faker</Text><Text style={styles.stepCopy}>Vote, spin the reveal, and see who fooled whom.</Text></View></View></View>
    <Text style={styles.footer}>Made for game nights and suspicious friends.</Text>
  </ScrollView></SafeAreaView>;
}

function makeStyles(palette) { return StyleSheet.create({ safe: { flex: 1, backgroundColor: palette.paper }, page: { width: '100%', maxWidth: 1080, alignSelf: 'center', paddingHorizontal: 24, paddingBottom: 44 }, topbar: { height: 76, flexDirection: 'row', alignItems: 'center', borderBottomWidth: 1, borderBottomColor: palette.line }, brandMark: { width: 38, height: 38, backgroundColor: palette.highlight, borderRadius: 13, justifyContent: 'center', alignItems: 'center', marginRight: 10 }, brandEmoji: { fontSize: 20 }, brand: { flex: 1, color: palette.ink, fontWeight: '900', letterSpacing: 1.2, fontSize: 13 }, profileButton: { flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 4 }, profileButtonText: { color: palette.ink, fontSize: 11, fontWeight: '800' }, hero: { alignItems: 'center', paddingTop: 42 }, heroTag: { backgroundColor: palette.highlight, borderRadius: 20, paddingVertical: 8, paddingHorizontal: 13 }, heroTagText: { color: palette.ink, fontWeight: '800', letterSpacing: 1.1, fontSize: 10 }, title: { color: palette.ink, fontSize: 42, lineHeight: 47, textAlign: 'center', fontWeight: '900', marginTop: 20, letterSpacing: -1.5 }, subtitle: { color: palette.muted, textAlign: 'center', fontSize: 15, marginTop: 12, maxWidth: 340, lineHeight: 23 }, scene: { width: 340, maxWidth: '100%', height: 190, marginTop: 23, alignItems: 'center', justifyContent: 'center' }, secretCard: { width: 190, height: 112, borderRadius: 18, backgroundColor: palette.card, alignItems: 'center', justifyContent: 'center', transform: [{ rotate: '-3deg' }], borderWidth: 1, borderColor: palette.line, elevation: 4 }, secretLabel: { fontSize: 9, letterSpacing: 1.2, fontWeight: '800', color: palette.muted }, secretWord: { fontSize: 28, fontWeight: '900', letterSpacing: 5, color: palette.coral, marginVertical: 4 }, secretHint: { fontSize: 10, color: palette.muted }, person: { position: 'absolute', width: 55, height: 55, borderRadius: 18, alignItems: 'center', justifyContent: 'center', borderWidth: 3, borderColor: palette.paper }, personFace: { fontSize: 27 }, personOne: { left: 26, top: 20, backgroundColor: palette.mint, transform: [{ rotate: '-10deg' }] }, personTwo: { right: 28, top: 27, backgroundColor: palette.yellow, transform: [{ rotate: '9deg' }] }, personThree: { left: 43, bottom: 12, backgroundColor: '#F8C3B9', transform: [{ rotate: '7deg' }] }, personFour: { right: 40, bottom: 9, backgroundColor: palette.blue, transform: [{ rotate: '-8deg' }] }, sparkle: { position: 'absolute', right: 82, top: 0, color: palette.coral, fontSize: 22 }, sparkleTwo: { position: 'absolute', left: 90, bottom: 3, color: '#75B996', fontSize: 20 }, panel: { width: '100%', maxWidth: 460, alignSelf: 'center', padding: 22, backgroundColor: palette.card, borderWidth: 1, borderColor: palette.line, borderRadius: 20, marginTop: 16 }, panelTitle: { color: palette.ink, fontSize: 21, fontWeight: '900' }, panelSub: { color: palette.muted, fontSize: 13, marginTop: 5, marginBottom: 17 }, input: { marginBottom: 12, borderWidth: 1, borderColor: palette.line, borderRadius: 12, padding: 14, color: palette.ink, backgroundColor: palette.input }, divider: { flexDirection: 'row', alignItems: 'center', marginVertical: 17, gap: 10 }, rule: { flex: 1, height: 1, backgroundColor: palette.line }, or: { color: palette.muted, fontSize: 9, fontWeight: '800', letterSpacing: 1 }, joinRow: { flexDirection: 'row', gap: 9 }, accountLink: { color: palette.coral, fontSize: 12, fontWeight: '800', textAlign: 'center', marginTop: 14 }, codeInput: { flex: 1, letterSpacing: 2, fontWeight: '800', marginBottom: 0 }, joinButton: { minWidth: 88, height: 50, justifyContent: 'center', alignItems: 'center', borderRadius: 12, backgroundColor: palette.coral }, joinText: { color: palette.actionText, fontSize: 14, fontWeight: '800' }, message: { color: palette.errorText, fontSize: 12, marginTop: 12, lineHeight: 18 }, how: { marginTop: 42 }, sectionTitle: { color: palette.ink, fontSize: 20, fontWeight: '900', textAlign: 'center' }, steps: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'center', marginTop: 20, gap: 12 }, step: { width: 210, alignItems: 'center', padding: 14 }, stepIcon: { width: 48, height: 48, borderRadius: 16, alignItems: 'center', justifyContent: 'center' }, stepTitle: { color: palette.ink, fontWeight: '800', fontSize: 14, marginTop: 11 }, stepCopy: { color: palette.muted, fontSize: 12, lineHeight: 18, textAlign: 'center', marginTop: 5 }, roomNotice: { marginTop: 14, padding: 14, borderRadius: 12, backgroundColor: palette.notice }, roomNoticeTitle: { fontWeight: '900', color: palette.ink, letterSpacing: 1.5 }, roomNoticeText: { color: palette.muted, fontSize: 12, marginTop: 4 }, footer: { color: palette.muted, textAlign: 'center', marginTop: 30, fontSize: 11 } }); }
