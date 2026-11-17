import js from '@eslint/js';
import globals from 'globals';

export default [
  { ignores: ['dist/**', 'node_modules/**', '.expo/**', 'coverage/**'] },
  js.configs.recommended,
  {
    files: ['**/*.js', '**/*.jsx'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      parserOptions: { ecmaFeatures: { jsx: true } },
      globals: { ...globals.browser, ...globals.node, __DEV__: 'readonly' },
    },
    rules: {
      'no-unused-vars': ['warn', { args: 'none', varsIgnorePattern: '^[A-Z]' }],
    },
  },
];
