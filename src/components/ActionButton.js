import React from 'react';
import { StyleSheet, Text, TouchableOpacity } from 'react-native';
import { palette, radius } from '../theme/palette';

export function ActionButton({ label, color = palette.ink, onPress, secondary = false, disabled = false }) {
  return (
    <TouchableOpacity
      accessibilityRole="button"
      accessibilityState={{ disabled }}
      disabled={disabled}
      onPress={onPress}
      style={[styles.button, { backgroundColor: secondary ? palette.card : color, borderColor: color, borderWidth: secondary ? 1 : 0 }, disabled && styles.disabled]}
    >
      <Text style={[styles.label, secondary && styles.secondaryLabel]}>{label}</Text>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  button: { minHeight: 50, justifyContent: 'center', alignItems: 'center', borderRadius: radius.control, paddingHorizontal: 16 },
  label: { color: '#FFFFFF', fontWeight: '800', fontSize: 15 },
  secondaryLabel: { color: palette.ink },
  disabled: { opacity: 0.55 },
});
