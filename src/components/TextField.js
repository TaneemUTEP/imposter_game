import React from 'react';
import { StyleSheet, TextInput } from 'react-native';
import { palette, radius } from '../theme/palette';

export function TextField({ accessibilityLabel, style, ...props }) {
  return <TextInput accessibilityLabel={accessibilityLabel} placeholderTextColor="#A6A3B2" style={[styles.input, style]} {...props} />;
}

const styles = StyleSheet.create({
  input: { height: 50, borderWidth: 1, borderColor: palette.line, borderRadius: radius.control, paddingHorizontal: 14, color: palette.ink, backgroundColor: '#FFFEFC', fontSize: 15 },
});
