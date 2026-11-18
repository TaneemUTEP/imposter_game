import React from 'react';
import { Text, TouchableOpacity } from 'react-native';
import { useTheme } from '../theme/ThemeContext';

/** Accessible control that switches the app-wide persisted theme palette. */
export function ThemeToggle() {
  const { mode, palette, toggleTheme } = useTheme();
  const nextMode = mode === 'light' ? 'dark' : 'light';
  return (
    <TouchableOpacity
      accessibilityRole="button"
      accessibilityLabel={`Switch to ${nextMode} theme`}
      onPress={toggleTheme}
      style={{ minHeight: 40, justifyContent: 'center', paddingHorizontal: 10, borderRadius: 12, borderWidth: 1, borderColor: palette.line, backgroundColor: palette.card }}
    >
      <Text style={{ color: palette.ink, fontSize: 12, fontWeight: '800' }}>{mode === 'light' ? '🌙 Dark' : '☀️ Light'}</Text>
    </TouchableOpacity>
  );
}
