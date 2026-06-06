import 'dotenv/config';
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import { z } from 'zod/v4';
import path from 'path';
import ui from '@nuxt/ui/vite';

const FRONTEND_PORT = z.coerce.number().parse(process.env.FRONTEND_PORT);
const BACKEND_PORT = z.coerce.number().parse(process.env.BACKEND_PORT);

const RAISED_CONTROL = 'raised';

// https://vite.dev/config/
export default defineConfig({
  root: path.resolve(__dirname, 'app'),
  plugins: [
    vue(),
    ui({
      ui: {
        colors: {
          primary: 'blue',
          neutral: 'stone',
        },
        button: {
          compoundVariants: [
            { color: 'neutral', variant: 'outline', class: RAISED_CONTROL },
            { color: 'neutral', variant: 'subtle', class: RAISED_CONTROL },
            { color: 'neutral', variant: 'soft', class: RAISED_CONTROL },
          ],
        },
        badge: {
          slots: {
            base: 'Badge',
          },
          compoundVariants: [
            {
              color: 'neutral',
              variant: 'outline',
              class: 'raised-edge text-muted bg-transparent',
            },
            // Tighten badge padding ~1px per axis vs Nuxt UI's size defaults
            // (md 8px/4px, sm 6px/4px). Plain marker classes styled in
            // theme.css — Tailwind can't generate arbitrary px utilities
            // referenced here, so a real (unlayered) CSS rule is the reliable
            // path. Applies globally to every md/sm badge.
            { size: 'md', class: 'badge-md' },
            { size: 'sm', class: 'badge-sm' },
          ],
        },
        checkbox: {
          slots: {
            base: 'rounded-xs',
          },
        },
        formField: {
          slots: {
            container: 'w-full',
          },
        },
        input: {
          slots: {
            root: 'w-full',
          },
        },
        inputMenu: {
          slots: {
            root: 'w-full',
          },
        },
        textarea: {
          slots: {
            root: 'w-full',
          },
        },
        dropdownMenu: {
          slots: {
            content: 'dark',
          },
        },
      },
    }),
  ],
  server: {
    port: FRONTEND_PORT,
    allowedHosts: true,
  },
  resolve: {
    alias: {
      '@app': path.resolve(__dirname, './app'),
      '@shared': path.resolve(__dirname, './shared'),
      '@db': path.resolve(__dirname, './backend/db'),
      '@api': path.resolve(__dirname, './backend/api'),
      '@integrations': path.resolve(__dirname, './backend/integrations'),
    },
  },
  define: {
    'import.meta.env.BACKEND_PORT': BACKEND_PORT,
  },
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes('node_modules')) return;
          if (id.includes('@nuxt/ui') || id.includes('reka-ui')) return 'vendor-ui';
          if (id.includes('@tanstack')) return 'vendor-query';
          if (id.includes('markdown-it') || id.includes('dompurify')) return 'vendor-markdown';
          if (id.includes('/vue-router/') || id.includes('/vue/') || id.includes('@vueuse'))
            return 'vendor-vue';
        },
      },
    },
  },
});
