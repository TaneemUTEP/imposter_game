import React from 'react';
import { StyleSheet, Text, TouchableOpacity } from 'react-native';
import { useTheme } from '../theme/ThemeContext';
import { radius } from '../theme/palette';

export function ActionButton({ label, color, onPress, secondary = false, disabled = false }) {
  const { palette } = useTheme();
  const styles = createStyles(palette);
  const buttonColor = color || palette.ink;
  return (
    <TouchableOpacity
      accessibilityRole="button"
      accessibilityState={{ disabled }}
      disabled={disabled}
      onPress={onPress}
      style={[styles.button, { backgroundColor: secondary ? palette.card : buttonColor, borderColor: buttonColor, borderWidth: secondary ? 1 : 0 }, disabled && styles.disabled]}
    >
      <Text style={[styles.label, secondary && styles.secondaryLabel]}>{label}</Text>
    </TouchableOpacity>
  );
}

function createStyles(palette) {
  return StyleSheet.create({
    button: { minHeight: 50, justifyContent: 'center', alignItems: 'center', borderRadius: radius.control, paddingHorizontal: 16 },
    label: { color: palette.actionText, fontWeight: '800', fontSize: 15 },
    secondaryLabel: { color: palette.ink },
    disabled: { opacity: 0.55 },
  });
}
