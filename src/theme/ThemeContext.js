import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';

const ThemeContext = createContext(null);
const THEME_KEY = 'imposter.theme';

const palettes = {
  light: {
    mode: 'light', ink: '#25243A', muted: '#77758B', paper: '#FFFCF7', card: '#FFFFFF', line: '#EEEAE2', actionText: '#25243A',
    coral: '#F26B5B', yellow: '#F6C85F', mint: '#BFE9D5', lilac: '#DCD4FF', blue: '#CDE8F4',
    input: '#FFFEFC', highlight: '#FFF2E8', clue: '#FFF8EB', notice: '#EAF7F0', errorBg: '#FCE7E4', errorText: '#AA4036',
  },
  dark: {
    mode: 'dark', ink: '#F4F1FA', muted: '#AAA5BA', paper: '#17151F', card: '#23202D', line: '#3A3547', actionText: '#25243A',
    coral: '#FF8274', yellow: '#D5AC4E', mint: '#80C8A5', lilac: '#685C91', blue: '#466D7D',
    input: '#2D2938', highlight: '#45302F', clue: '#393125', notice: '#263A32', errorBg: '#492D31', errorText: '#FFAAA2',
  },
};

export function ThemeProvider({ children }) {
  const [mode, setMode] = useState('light');

  useEffect(() => {
    AsyncStorage.getItem(THEME_KEY).then(saved => {
      if (saved === 'light' || saved === 'dark') setMode(saved);
    }).catch(() => {});
  }, []);

  const toggleTheme = useCallback(() => {
    setMode(current => {
      const next = current === 'light' ? 'dark' : 'light';
      AsyncStorage.setItem(THEME_KEY, next).catch(() => {});
      return next;
    });
  }, []);

  const value = useMemo(() => ({ mode, palette: palettes[mode], toggleTheme }), [mode, toggleTheme]);
  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme() {
  const theme = useContext(ThemeContext);
  if (!theme) throw new Error('useTheme must be used inside ThemeProvider');
  return theme;
}
