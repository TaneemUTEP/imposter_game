import React from 'react';
import { StyleSheet, TextInput } from 'react-native';
import { useTheme } from '../theme/ThemeContext';
import { radius } from '../theme/palette';

export function TextField({ accessibilityLabel, style, ...props }) {
  const { palette } = useTheme();
  const styles = createStyles(palette);
  return <TextInput accessibilityLabel={accessibilityLabel} placeholderTextColor={palette.muted} style={[styles.input, style]} {...props} />;
}

function createStyles(palette) {
  return StyleSheet.create({
    input: { height: 50, borderWidth: 1, borderColor: palette.line, borderRadius: radius.control, paddingHorizontal: 14, color: palette.ink, backgroundColor: palette.input, fontSize: 15 },
  });
}
