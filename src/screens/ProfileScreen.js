import React, { useEffect, useState } from 'react';
import { Alert, Image, ScrollView, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';
import * as ImagePicker from 'expo-image-picker';
import * as ImageManipulator from 'expo-image-manipulator';
import { ActionButton } from '../components/ActionButton';
import { ThemeToggle } from '../components/ThemeToggle';
import { getAuthErrorMessage } from '../lib/authErrors';
import { createEmailAccount, signInWithEmail, supabase } from '../lib/supabase';
import { useTheme } from '../theme/ThemeContext';

export function ProfileScreen({ initialName = '', onAccountReady, onClose }) {
  const { palette } = useTheme();
  const styles = createStyles(palette);
  const [profile, setProfile] = useState(null);
  const [session, setSession] = useState(null);
  const [name, setName] = useState(initialName);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [photo, setPhoto] = useState(null);
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [authMode, setAuthMode] = useState('create');

  useEffect(() => { loadProfile(); }, []);

  async function loadProfile() {
    if (!supabase) {
      setMessage('Online accounts are not configured yet. Please try again later.');
      setLoading(false);
      return;
    }
    try {
      const { data: { session: currentSession }, error: sessionError } = await supabase.auth.getSession();
      if (sessionError) throw sessionError;
      setSession(currentSession);
      if (!currentSession) {
        setProfile(null);
        setLoading(false);
        return;
      }
      const { data, error } = await supabase.rpc('get_my_profile');
      if (error) throw error;
      setProfile(data);
      setName(data?.display_name || currentSession.user.user_metadata?.display_name || initialName);
      if (data?.avatar_path) {
        const { data: signed } = await supabase.storage.from('avatars').createSignedUrl(data.avatar_path, 3600);
        setPhoto(signed?.signedUrl || null);
      }
    } catch (error) {
      setMessage(getAuthErrorMessage(error));
    } finally {
      setLoading(false);
    }
  }

  async function submitAccount() {
    setBusy(true);
    setMessage('');
    try {
      if (authMode === 'create') {
        if (!name.trim()) throw new Error('Add the name you want friends to see before creating your account.');
        const result = await createEmailAccount(email, password, name);
        if (result.session) {
          onAccountReady(name.trim());
        } else {
          setAuthMode('signin');
          setMessage('Account started. Check your email for a confirmation link, then return here and sign in.');
        }
      } else {
        const result = await signInWithEmail(email, password);
        const accountName = name.trim() || result.user.user_metadata?.display_name || '';
        onAccountReady(accountName);
      }
    } catch (error) {
      setMessage(getAuthErrorMessage(error));
    } finally {
      setBusy(false);
    }
  }

  async function saveName() {
    if (!profile?.id) {
      setMessage('Your name will be saved when you create or join your first room.');
      return;
    }
    setBusy(true);
    setMessage('');
    try {
      const { error } = await supabase.rpc('update_my_profile', { p_name: name.trim() });
      if (error) throw error;
      setMessage('Name saved.');
      await loadProfile();
    } catch (error) {
      setMessage(getAuthErrorMessage(error));
    } finally {
      setBusy(false);
    }
  }

  async function choosePhoto() {
    const permission = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (!permission.granted) {
      setMessage('Allow photo access to choose a profile image.');
      return;
    }
    const result = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], allowsEditing: true, aspect: [1, 1], quality: 0.85 });
    if (result.canceled) return;
    setBusy(true);
    setMessage('');
    try {
      const asset = result.assets[0];
      const processed = await ImageManipulator.manipulateAsync(asset.uri, [{ resize: { width: 512, height: 512 } }], { compress: 0.82, format: ImageManipulator.SaveFormat.JPEG });
      const blob = await (await fetch(processed.uri)).blob();
      if (blob.size > 5 * 1024 * 1024) throw new Error('Photo must be smaller than 5 MB.');
      const { data: { user } } = await supabase.auth.getUser();
      const path = `${user.id}/avatar.jpg`;
      const { error } = await supabase.storage.from('avatars').upload(path, blob, { contentType: 'image/jpeg', upsert: true });
      if (error) throw error;
      const { error: profileError } = await supabase.from('profiles').update({ avatar_path: path }).eq('id', user.id);
      if (profileError) throw profileError;
      setMessage('Profile photo updated.');
      await loadProfile();
    } catch (error) {
      setMessage(getAuthErrorMessage(error));
    } finally {
      setBusy(false);
    }
  }

  async function saveGuestAccount() {
    setBusy(true);
    setMessage('');
    try {
      const { error } = await supabase.auth.updateUser({ email: email.trim(), password });
      if (error) throw error;
      setMessage('We sent a verification email. Confirm it to secure this guest profile and keep its stats.');
    } catch (error) {
      setMessage(getAuthErrorMessage(error));
    } finally {
      setBusy(false);
    }
  }

  async function signOut() {
    await supabase.auth.signOut();
    onClose();
  }

  async function deleteAccount() {
    const remove = async () => {
      setBusy(true);
      try {
        const { error } = await supabase.rpc('delete_my_account');
        if (error) throw error;
        await supabase.auth.signOut();
        onClose();
      } catch (error) {
        setMessage(getAuthErrorMessage(error));
      } finally {
        setBusy(false);
      }
    };
    if (typeof window !== 'undefined' && window.confirm) {
      if (window.confirm('Delete your account and profile photo? Completed match records will remain anonymized.')) await remove();
    } else {
      Alert.alert('Delete account', 'Delete your account and profile photo?', [
        { text: 'Cancel', style: 'cancel' }, { text: 'Delete', style: 'destructive', onPress: remove },
      ]);
    }
  }

  if (loading) return <View style={styles.loading}><Text style={styles.help}>Loading your profile…</Text></View>;

  if (!session) return (
    <ScrollView contentContainerStyle={styles.page}>
      <View style={styles.header}><TouchableOpacity accessibilityRole="button" onPress={onClose}><Text style={styles.back}>← Back</Text></TouchableOpacity><Text style={styles.heading}>Your account</Text><ThemeToggle /></View>
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Play without signing up</Text>
        <Text style={styles.help}>A guest profile is quickest. An email account lets you sign in on another device and keep your stats.</Text>
        <View style={styles.modeRow}>
          <TouchableOpacity accessibilityRole="button" accessibilityState={{ selected: authMode === 'create' }} onPress={() => { setAuthMode('create'); setMessage(''); }} style={[styles.modeButton, authMode === 'create' && styles.modeSelected]}><Text style={[styles.modeText, authMode === 'create' && styles.modeTextSelected]}>Create account</Text></TouchableOpacity>
          <TouchableOpacity accessibilityRole="button" accessibilityState={{ selected: authMode === 'signin' }} onPress={() => { setAuthMode('signin'); setMessage(''); }} style={[styles.modeButton, authMode === 'signin' && styles.modeSelected]}><Text style={[styles.modeText, authMode === 'signin' && styles.modeTextSelected]}>Sign in</Text></TouchableOpacity>
        </View>
        {authMode === 'create' ? <><Text style={styles.fieldLabel}>Name friends will see</Text><TextInput accessibilityLabel="Name friends will see" value={name} onChangeText={setName} maxLength={24} placeholder="Your name" placeholderTextColor={palette.muted} style={styles.input} /></> : null}
        <Text style={styles.fieldLabel}>Email</Text><TextInput accessibilityLabel="Email" value={email} onChangeText={setEmail} placeholder="you@example.com" autoCapitalize="none" autoComplete="email" keyboardType="email-address" style={styles.input} />
        <Text style={styles.fieldLabel}>Password</Text><TextInput accessibilityLabel="Password" value={password} onChangeText={setPassword} placeholder="At least 8 characters" secureTextEntry autoComplete={authMode === 'create' ? 'new-password' : 'current-password'} style={styles.input} />
        <ActionButton label={busy ? 'Please wait…' : authMode === 'create' ? 'Create free account' : 'Sign in'} color={palette.coral} onPress={submitAccount} disabled={busy || !email.includes('@') || password.length < 8 || (authMode === 'create' && !name.trim())} />
        <Text style={styles.footnote}>You can play as a guest without an email. If guest access is off for this game, use an email account or ask the host to enable guest sign-ins.</Text>
      </View>
      {message ? <Text accessibilityRole="alert" style={styles.message}>{message}</Text> : null}
    </ScrollView>
  );

  const isGuest = session.user.is_anonymous;
  return (
    <ScrollView contentContainerStyle={styles.page}>
      <View style={styles.header}><TouchableOpacity accessibilityRole="button" onPress={onClose}><Text style={styles.back}>← Back</Text></TouchableOpacity><Text style={styles.heading}>{isGuest ? 'Guest profile' : 'Your profile'}</Text><ThemeToggle /></View>
      {message ? <Text accessibilityRole="alert" style={styles.message}>{message}</Text> : null}
      <View style={styles.card}>
        <TouchableOpacity accessibilityRole="button" accessibilityLabel="Choose profile photo" onPress={choosePhoto} style={styles.photo}>{photo ? <Image source={{ uri: photo }} style={styles.image} /> : <Text style={styles.photoEmoji}>🙂</Text>}</TouchableOpacity>
        <Text style={styles.help}>Tap to add a profile photo</Text>
        <Text style={styles.fieldLabel}>Your player name</Text>
        <TextInput accessibilityLabel="Display name" value={name} onChangeText={setName} maxLength={24} placeholder="Your name" placeholderTextColor={palette.muted} style={styles.input} />
        <ActionButton label="Save name" color={palette.coral} onPress={saveName} disabled={busy} />
      </View>
      <View style={styles.card}><Text style={styles.cardTitle}>Your stats</Text>{profile?.id ? <><Metric label="Rounds played" value={profile.rounds}/><Metric label="Imposter escapes" value={`${profile.escapes}/${profile.imposter_rounds}`}/><Metric label="Escape rate" value={profile.escape_rate===null?'Not enough games':`${Math.round(profile.escape_rate*100)}%`}/><Metric label="Correct civilian picks" value={profile.accuracy===null?'Not enough games':`${Math.round(profile.accuracy*100)}%`}/><Metric label="Players fooled" value={profile.fooled}/><Text style={styles.cardTitle}>Titles</Text>{profile.achievements?.length?profile.achievements.map((item,index)=><Text key={`${item.title}-${index}`} style={styles.titleRow}>🏅 {item.title}</Text>):<Text style={styles.help}>Finish a match to earn your first title.</Text>}</>:<Text style={styles.help}>Your stats will appear after your first scored round.</Text>}</View>
      {isGuest ? <View style={styles.card}><Text style={styles.cardTitle}>Keep this profile on other devices</Text><Text style={styles.help}>Add an email and password to turn this guest profile into an account. We’ll email you a verification link; your game stats stay with this profile.</Text><Text style={styles.fieldLabel}>Email</Text><TextInput accessibilityLabel="Email to save guest profile" value={email} onChangeText={setEmail} placeholder="you@example.com" autoCapitalize="none" autoComplete="email" keyboardType="email-address" style={styles.input}/><Text style={styles.fieldLabel}>Password</Text><TextInput accessibilityLabel="Password to save guest profile" value={password} onChangeText={setPassword} placeholder="At least 8 characters" secureTextEntry style={styles.input}/><ActionButton label="Save profile with email" color={palette.ink} onPress={saveGuestAccount} disabled={busy||!email.includes('@')||password.length<8}/></View> : <View style={styles.card}><Text style={styles.cardTitle}>Account</Text><Text style={styles.help}>Signed in as {session.user.email}</Text></View>}
      <View style={styles.card}><TouchableOpacity accessibilityRole="button" onPress={signOut} style={styles.signOut}><Text style={styles.signOutText}>Sign out</Text></TouchableOpacity><TouchableOpacity accessibilityRole="button" onPress={deleteAccount} style={styles.signOut}><Text style={styles.deleteText}>Delete account</Text></TouchableOpacity></View>
    </ScrollView>
  );
}

function Metric({ label, value }) {
  const { palette } = useTheme();
  const styles = createStyles(palette);
  return <View style={styles.metric}><Text style={styles.metricLabel}>{label}</Text><Text style={styles.metricValue}>{value}</Text></View>;
}

function createStyles(palette) {
  return StyleSheet.create({
    page: { width: '100%', maxWidth: 680, alignSelf: 'center', padding: 24, paddingBottom: 48 },
    loading: { flex: 1, justifyContent: 'center', alignItems: 'center', padding: 24 },
    header: { flexDirection: 'row', alignItems: 'center', gap: 12, marginBottom: 18 },
    back: { color: palette.muted, fontWeight: '700', paddingVertical: 12 },
    heading: { color: palette.ink, fontSize: 25, fontWeight: '900', flex: 1 },
    card: { backgroundColor: palette.card, borderColor: palette.line, borderWidth: 1, borderRadius: 18, padding: 20, marginBottom: 14 },
    cardTitle: { color: palette.ink, fontSize: 18, fontWeight: '900', marginBottom: 8 },
    help: { color: palette.muted, fontSize: 13, lineHeight: 19, marginVertical: 10 },
    footnote: { color: palette.muted, fontSize: 12, lineHeight: 18, marginTop: 14 },
    photo: { width: 88, height: 88, borderRadius: 44, backgroundColor: palette.yellow, alignSelf: 'center', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' },
    image: { width: 88, height: 88 }, photoEmoji: { fontSize: 38 },
    input: { minHeight: 48, borderWidth: 1, borderColor: palette.line, borderRadius: 10, paddingHorizontal: 12, marginVertical: 6, color: palette.ink, backgroundColor: palette.input },
    fieldLabel: { color: palette.ink, fontSize: 12, fontWeight: '800', marginTop: 8 },
    modeRow: { flexDirection: 'row', backgroundColor: palette.paper, borderRadius: 12, padding: 4, marginVertical: 10 },
    modeButton: { flex: 1, alignItems: 'center', justifyContent: 'center', minHeight: 42, borderRadius: 9 },
    modeSelected: { backgroundColor: palette.card, borderWidth: 1, borderColor: palette.line },
    modeText: { color: palette.muted, fontWeight: '700' }, modeTextSelected: { color: palette.ink },
    metric: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 10, borderBottomWidth: 1, borderColor: palette.line },
    metricLabel: { color: palette.muted }, metricValue: { color: palette.ink, fontWeight: '800' },
    titleRow: { paddingVertical: 6, color: palette.ink, fontWeight: '700' },
    message: { color: palette.errorText, backgroundColor: palette.errorBg, padding: 12, marginBottom: 12, borderRadius: 10, lineHeight: 19 },
    signOut: { padding: 12, alignItems: 'center' }, signOutText: { color: palette.muted, fontWeight: '700' }, deleteText: { color: palette.errorText, fontWeight: '800' },
  });
}
