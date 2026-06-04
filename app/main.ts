import '@app/assets/theme.css';
import { createApp } from 'vue';
import App from '@app/AppLayout.vue';
import { VueQueryPlugin } from '@tanstack/vue-query';
import { router } from '@app/router';
import ui from '@nuxt/ui/vue-plugin';
import { createHead } from '@unhead/vue/client';
import { addCollection } from '@iconify/vue';
import lucideIcons from '@iconify-json/lucide/icons.json';

addCollection(lucideIcons);

const app = createApp(App);
const head = createHead({
  init: [
    {
      title: 'Enchiridion',
    },
  ],
});

app.use(router);
app.use(ui);
app.use(head);

app.use(VueQueryPlugin, {
  enableDevtoolsV6Plugin: true,
  queryClientConfig: {
    defaultOptions: {
      queries: {
        networkMode: 'always',
        retry: false,
        // Local single-user app: cached data is almost always fine for a minute,
        // and mutations explicitly invalidate the right keys anyway. Without
        // this, every page navigation refetches everything because the default
        // staleTime is 0, which causes a perceptible flash on every nav.
        staleTime: 60_000,
      },
    },
  },
});

app.mount('#app');
