<template>
  <component
    v-if="shell"
    :is="shell"
  />
  <div
    v-else
    style="padding: 2rem; color: var(--ui-text-muted)"
  >
    Unknown design-lab exploration: <code>{{ slug }}</code>
  </div>
</template>

<script setup lang="ts">
// Dispatcher for /design-lab/:slug — mounts that exploration's own Shell.vue so
// multiple explorations can coexist under one route. Each Shell is scoped to
// its own folder (its variant globs are relative to itself).
import { computed, defineAsyncComponent } from 'vue';
import { useRoute } from 'vue-router';

const shells = import.meta.glob('./*/Shell.vue');
const route = useRoute();
const slug = computed(() => String(route.params.slug));
const shell = computed(() => {
  const loader = shells[`./${slug.value}/Shell.vue`];
  return loader ? defineAsyncComponent(loader as () => Promise<Record<string, unknown>>) : null;
});
</script>
