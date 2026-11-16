import React from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { palette } from '../theme/palette';

export function Avatar({ label = '🙂', color = palette.yellow, size = 38 }) {
  return <View accessibilityRole="image" accessibilityLabel="Player avatar" style={[styles.avatar, { width: size, height: size, borderRadius: size / 2, backgroundColor: color }]}><Text style={{ fontSize: size * 0.5 }}>{label}</Text></View>;
}

const styles = StyleSheet.create({ avatar: { justifyContent: 'center', alignItems: 'center' } });
