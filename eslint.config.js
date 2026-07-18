import js from '@eslint/js';
import globals from 'globals';
import tseslint from 'typescript-eslint';
import pluginVue from 'eslint-plugin-vue';
import { defineConfig } from 'eslint/config';
import prettier from 'eslint-config-prettier';

export default defineConfig([
  {
    ignores: [
      // Build output (`pnpm build` writes app/dist).
      '**/dist/**',
      // Scratch playground, exempt from lint (and from type checking — see
      // tsconfig.app.json) so experiments can't redden the real gates.
      'app/design-lab/**',
    ],
  },
  {
    files: ['**/*.{js,ts,vue}'],
    plugins: { js },
    extends: ['js/recommended'],
    languageOptions: {
      globals: {
        defineShortcuts: true,
        useToast: true,
        chrome: true,
        ...globals.browser,
        ...globals.node,
      },
    },
  },
  {
    files: ['**/*.vue'],
    languageOptions: {
      parserOptions: {
        parser: tseslint.parser,
      },
    },
  },
  js.configs.recommended,
  tseslint.configs.recommended,
  pluginVue.configs['flat/strongly-recommended'],
  {
    files: ['**/*.{js,ts,vue}'],
    rules: {
      'no-console': 'error',
      // Allow deliberately-unused names when underscore-prefixed — e.g. the
      // `_next` param Express requires for error-middleware arity.
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^_',
        },
      ],
      'vue/attribute-hyphenation': 'off',
      'vue/require-default-prop': 'off',
      'vue/no-undef-properties': ['error'],
      'vue/enforce-style-attribute': [
        'error',
        {
          allow: ['scoped'],
        },
      ],
      'vue/prefer-true-attribute-shorthand': ['error', 'always'],
      'vue/v-on-event-hyphenation': ['error', 'never'],
      'vue/attributes-order': [
        'error',
        {
          order: [
            'LIST_RENDERING',
            'CONDITIONALS',
            'RENDER_MODIFIERS',
            'UNIQUE',
            'DEFINITION',
            'GLOBAL',
            'TWO_WAY_BINDING',
            'SLOT',
            'ATTR_STATIC',
            'ATTR_DYNAMIC',
            'OTHER_DIRECTIVES',
            'CONTENT',
            'ATTR_SHORTHAND_BOOL',
            'EVENTS',
          ],
          alphabetical: false,
        },
      ],
      'vue/define-macros-order': [
        'error',
        {
          order: ['defineOptions', 'defineModel', 'defineEmits', 'defineProps', 'defineSlots'],
        },
      ],
    },
  },
  prettier,
]);
