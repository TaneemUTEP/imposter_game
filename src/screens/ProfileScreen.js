import React, { useEffect, useState } from 'react';
import { Alert, Image, ScrollView, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';
import * as ImagePicker from 'expo-image-picker';
import * as ImageManipulator from 'expo-image-manipulator';
import { palette } from '../theme/palette';
import { ActionButton } from '../components/ActionButton';
import { supabase } from '../lib/supabase';

export function ProfileScreen({ onClose }) {
  const [profile,setProfile]=useState(null);
  const [name,setName]=useState('');
  const [email,setEmail]=useState('');
  const [password,setPassword]=useState('');
  const [photo,setPhoto]=useState(null);
  const [message,setMessage]=useState('');
  const [busy,setBusy]=useState(false);

  async function loadProfile(){
    if(!supabase) return;
    const {data,error}=await supabase.rpc('get_my_profile');
    if(error){setMessage(error.message);return;}
    setProfile(data);setName(data.display_name||'');
    if(data.avatar_path){const {data:signed}=await supabase.storage.from('avatars').createSignedUrl(data.avatar_path,3600);setPhoto(signed?.signedUrl||null);}
  }
  useEffect(()=>{loadProfile();},[]);

  async function saveName(){setBusy(true);setMessage('');try{const {error}=await supabase.rpc('update_my_profile',{p_name:name.trim()});if(error)throw error;setMessage('Profile saved.');await loadProfile();}catch(e){setMessage(e.message);}finally{setBusy(false);}}
  async function choosePhoto(){
    const permission=await ImagePicker.requestMediaLibraryPermissionsAsync();
    if(!permission.granted){setMessage('Allow photo access to choose a profile image.');return;}
    const result=await ImagePicker.launchImageLibraryAsync({mediaTypes:['images'],allowsEditing:true,aspect:[1,1],quality:0.85});
    if(result.canceled)return;
    setBusy(true);setMessage('');
    try{
      const asset=result.assets[0];
      const processed=await ImageManipulator.manipulateAsync(asset.uri,[{resize:{width:512,height:512}}],{compress:0.82,format:ImageManipulator.SaveFormat.JPEG});
      const response=await fetch(processed.uri);const blob=await response.blob();
      if(blob.size>5*1024*1024)throw new Error('Photo must be smaller than 5 MB.');
      const {data:{user}}=await supabase.auth.getUser();
      const path=`${user.id}/avatar.jpg`;
      const {error}=await supabase.storage.from('avatars').upload(path,blob,{contentType:'image/jpeg',upsert:true});if(error)throw error;
      const {error:profileError}=await supabase.from('profiles').update({avatar_path:path}).eq('id',user.id);if(profileError)throw profileError;
      setMessage('Profile photo updated.');await loadProfile();
    }catch(e){setMessage(e.message||'Could not upload that photo.');}finally{setBusy(false);}
  }
  async function upgradeGuest(){setBusy(true);setMessage('');try{const {error}=await supabase.auth.updateUser({email:email.trim(),password});if(error)throw error;setMessage('Check your email to verify the address and finish securing this account.');}catch(e){setMessage(e.message);}finally{setBusy(false);}}
  async function signOut(){await supabase.auth.signOut();onClose();}
  async function deleteAccount(){
    const remove=async()=>{setBusy(true);try{const {error}=await supabase.rpc('delete_my_account');if(error)throw error;await supabase.auth.signOut();onClose();}catch(e){setMessage(e.message);}finally{setBusy(false);}};
    if(typeof window!=='undefined'&&window.confirm){if(window.confirm('Delete your account and profile photo? Completed match records will remain anonymized.'))await remove();}
    else Alert.alert('Delete account','Delete your account and profile photo?', [{text:'Cancel',style:'cancel'},{text:'Delete',style:'destructive',onPress:remove}]);
  }

  return <ScrollView contentContainerStyle={styles.page}><TouchableOpacity accessibilityRole="button" onPress={onClose}><Text style={styles.back}>← Back</Text></TouchableOpacity><Text style={styles.heading}>Your profile</Text>
    <View style={styles.card}><TouchableOpacity accessibilityRole="button" accessibilityLabel="Choose profile photo" onPress={choosePhoto} style={styles.photo}>{photo?<Image source={{uri:photo}} style={styles.image}/>:<Text style={styles.photoEmoji}>🙂</Text>}</TouchableOpacity><Text style={styles.help}>Tap to add a profile photo</Text><TextInput accessibilityLabel="Display name" value={name} onChangeText={setName} maxLength={24} style={styles.input}/><ActionButton label="Save profile" color={palette.coral} onPress={saveName} disabled={busy}/></View>
    <View style={styles.card}><Text style={styles.cardTitle}>Your stats</Text>{profile?<><Metric label="Rounds played" value={profile.rounds}/><Metric label="Imposter escapes" value={`${profile.escapes}/${profile.imposter_rounds}`}/><Metric label="Escape rate" value={profile.escape_rate===null?'Not enough games':`${Math.round(profile.escape_rate*100)}%`}/><Metric label="Correct civilian picks" value={profile.accuracy===null?'Not enough games':`${Math.round(profile.accuracy*100)}%`}/><Metric label="Players fooled" value={profile.fooled}/><Text style={styles.cardTitle}>Titles</Text>{profile.achievements?.length?profile.achievements.map((item,index)=><Text key={`${item.title}-${index}`} style={styles.titleRow}>🏅 {item.title}</Text>):<Text style={styles.help}>Finish a match to earn your first title.</Text>}</>:<Text style={styles.help}>Stats appear after your first scored round.</Text>}</View>
    <View style={styles.card}><Text style={styles.cardTitle}>Keep your profile</Text><Text style={styles.help}>Secure this guest profile with an email and password. You keep its stats on this device.</Text><TextInput accessibilityLabel="Email" value={email} onChangeText={setEmail} placeholder="Email" autoCapitalize="none" keyboardType="email-address" style={styles.input}/><TextInput accessibilityLabel="Password" value={password} onChangeText={setPassword} placeholder="Password" secureTextEntry style={styles.input}/><ActionButton label="Add email and password" color={palette.ink} onPress={upgradeGuest} disabled={busy||!email.includes('@')||password.length<8}/><TouchableOpacity onPress={signOut} style={styles.signOut}><Text style={styles.signOutText}>Sign out</Text></TouchableOpacity><TouchableOpacity onPress={deleteAccount} style={styles.signOut}><Text style={styles.deleteText}>Delete account</Text></TouchableOpacity></View>
    {message?<Text accessibilityRole="alert" style={styles.message}>{message}</Text>:null}</ScrollView>;
}
function Metric({label,value}){return <View style={styles.metric}><Text style={styles.metricLabel}>{label}</Text><Text style={styles.metricValue}>{value}</Text></View>;}

const styles=StyleSheet.create({page:{width:'100%',maxWidth:680,alignSelf:'center',padding:24,paddingBottom:48},back:{color:palette.muted,fontWeight:'700',paddingVertical:12},heading:{color:palette.ink,fontSize:30,fontWeight:'900',marginBottom:18},card:{backgroundColor:'#fff',borderColor:palette.line,borderWidth:1,borderRadius:18,padding:20,marginBottom:14},cardTitle:{color:palette.ink,fontSize:18,fontWeight:'900',marginBottom:12},photo:{width:88,height:88,borderRadius:44,backgroundColor:palette.yellow,alignSelf:'center',alignItems:'center',justifyContent:'center',overflow:'hidden'},image:{width:88,height:88},photoEmoji:{fontSize:38},help:{color:palette.muted,fontSize:13,lineHeight:19,textAlign:'center',marginVertical:10},input:{minHeight:48,borderWidth:1,borderColor:palette.line,borderRadius:10,paddingHorizontal:12,marginVertical:6,color:palette.ink},metric:{flexDirection:'row',justifyContent:'space-between',paddingVertical:10,borderBottomWidth:1,borderColor:palette.line},metricLabel:{color:palette.muted},metricValue:{color:palette.ink,fontWeight:'800'},message:{color:'#A54A3E',margin:8},titleRow:{paddingVertical:6,color:palette.ink,fontWeight:'700'},signOut:{padding:14,alignItems:'center'},signOutText:{color:palette.muted,fontWeight:'700'},deleteText:{color:'#B33B32',fontWeight:'800'}});
