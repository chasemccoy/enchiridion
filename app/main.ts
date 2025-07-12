import '@app/assets/theme.css';
import { createApp } from 'vue';
import App from '@app/AppLayout.vue';
import { VueQueryPlugin } from '@tanstack/vue-query';
import { router } from '@app/router';
import ui from '@nuxt/ui/vue-plugin';
import { createHead } from '@unhead/vue/client';

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
      },
    },
  },
});

app.mount('#app');
