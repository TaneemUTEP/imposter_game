import React from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { useTheme } from '../theme/ThemeContext';

export function Avatar({ label = '🙂', color, size = 38 }) {
  const { palette } = useTheme();
  return <View accessibilityRole="image" accessibilityLabel="Player avatar" style={[styles.avatar, { width: size, height: size, borderRadius: size / 2, backgroundColor: color || palette.yellow }]}><Text style={{ fontSize: size * 0.5 }}>{label}</Text></View>;
}

const styles = StyleSheet.create({ avatar: { justifyContent: 'center', alignItems: 'center' } });
