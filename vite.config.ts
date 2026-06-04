import 'dotenv/config';
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import { z } from 'zod/v4';
import path from 'path';
import ui from '@nuxt/ui/vite';

const FRONTEND_PORT = z.coerce.number().parse(process.env.FRONTEND_PORT);
const BACKEND_PORT = z.coerce.number().parse(process.env.BACKEND_PORT);

// https://vite.dev/config/
export default defineConfig({
  root: path.resolve(__dirname, 'app'),
  plugins: [
    vue(),
    ui({
      ui: {
        colors: {
          primary: 'emerald',
          neutral: 'stone',
        },
        badge: {
          slots: {
            base: 'Badge',
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
