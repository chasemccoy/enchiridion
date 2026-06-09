<template>
  <SplitViewLayout
    v-if="!isEmpty"
    v-model="data"
    :recordCardProps="(record) => ({ to: `/inbox/record/${record.slug}` })"
    :isEmpty
  >
    <RouterView />
  </SplitViewLayout>
  <div
    v-else
    class="InboxView__emptyState"
  >
    <svg
      viewBox="0 0 40 40"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M32.381 0C37.0476 0 38.8571 2 39.0476 3.80952L39.1457 5.00145L39.4461 9.51798L39.999 18.6492L40 33.3333C40 38 37.2381 40 32.381 40H7.61905C2.76191 40 0 38.0952 0 33.3333L0.00311851 18.6192L0.952381 3.80952C1.04762 2 3.04762 0 7.61905 0H32.381ZM33.3333 7.61905H6.66667C6.40476 7.61905 5.90278 8.17923 5.82093 8.85946L5.60032 13.9987C5.47247 16.7529 5.33333 19.619 5.33333 19.619L5.35028 19.7421C5.40923 20.0722 5.66071 20.9524 6.66667 20.9524H9.33333C11.4286 20.9524 13.3333 23.2381 13.3333 24.9524V32.9524C13.3333 33.5238 14 34.2857 14.6667 34.2857H25.3333C26.1905 34.2857 26.6667 33.3333 26.6667 32.9524V24.9524C26.6667 23.0476 28.4762 20.9524 30.6667 20.9524H33.3333C34.6667 20.9524 34.6667 19.619 34.6667 19.619L34.3563 12.1129C34.2857 10.5608 34.2222 9.33333 34.1905 9.14286C34.1905 8.57143 33.7143 7.61905 33.3333 7.61905Z"
        fill="currentColor"
      />
    </svg>
  </div>
</template>

<script setup lang="ts">
import SplitViewLayout from '@app/components/SplitViewLayout.vue';
import useRecords from '@app/composables/useRecords';
import { RouteName } from '@app/router';
import { computed, onActivated, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';

const route = useRoute();
const router = useRouter();

const isEmpty = computed(() => !data.value || data.value.length === 0);

const { data } = useRecords({
  limit: 100,
  filters: {
    isCurated: false,
    hideUntitledChildren: true,
    // Notes have no curation pipeline and live on /notes — keep them out of the inbox.
    type: { notIn: ['note'] },
  },
  orderBy: [
    {
      field: 'recordCreatedAt',
      direction: 'desc',
    },
    {
      field: 'contentCreatedAt',
      direction: 'desc',
    },
    {
      field: 'type',
      direction: 'asc',
    },
  ],
});

// Auto-select the first record only when the user is sitting on the bare
// /inbox path (route.name === 'inbox'). If they're on /inbox/record/foo we
// leave their selection alone.
//
// Runs from two sources because KeepAlive keeps this component mounted across
// navigations: once when data loads (watch), and again every time the user
// re-activates the view by clicking Inbox in the nav (onActivated). Both
// paths share the same guard, so it's safe to fire either way.
function selectFirstIfBare() {
  if (route.name !== RouteName.inbox) return;
  const firstRecord = data.value?.[0];
  if (!firstRecord) return;
  router.push(`/inbox/record/${firstRecord.slug}`);
}

// When the currently-selected record drops out of the inbox list (curated or
// deleted), advance to the record that now occupies the same slot. Falls back
// to the last record if we were at the tail, or to /inbox when the list is
// empty.
watch(
  data,
  (next, prev) => {
    selectFirstIfBare();

    const currentSlug = route.params.slug as string | undefined;
    if (!currentSlug || !prev || !next) return;
    if (next.some((record) => record.slug === currentSlug)) return;

    const prevIndex = prev.findIndex((record) => record.slug === currentSlug);
    if (prevIndex < 0) return;

    if (next.length === 0) {
      router.push('/inbox');
      return;
    }

    const nextRecord = next[Math.min(prevIndex, next.length - 1)];
    if (nextRecord) router.push(`/inbox/record/${nextRecord.slug}`);
  },
  { immediate: true },
);

onActivated(selectFirstIfBare);
</script>

<style scoped>
.InboxView__emptyState {
  color: var(--ui-text-dimmed);
  display: grid;
  place-items: center;
  height: 100%;
  opacity: 0.25;

  svg {
    width: 64px;
  }
}
</style>
