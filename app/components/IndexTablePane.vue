<template>
  <div
    ref="root"
    class="IndexTablePane"
  >
    <RecordTable
      v-if="model"
      v-model="model"
      :hideColumns="hideColumns"
    />
  </div>
</template>

<script setup lang="ts">
import RecordTable from '@app/components/RecordTable.vue';
import type { ListRecordsAPIResponse } from '@db/queries/records';
import { nextTick, onActivated, onBeforeUnmount, onMounted, useTemplateRef } from 'vue';

const model = defineModel<ListRecordsAPIResponse>();

defineProps<{
  hideColumns?: string[];
}>();

const root = useTemplateRef<HTMLDivElement>('root');

// Scroll preservation across KeepAlive cycles, mirroring SplitViewLayout: the
// browser resets an internal scroller's position when it's detached/reattached
// (which is what KeepAlive does), and scrollTop already reads 0 by
// onDeactivated — so track it continuously via a passive listener.
let savedScrollTop = 0;
function handleScroll() {
  if (root.value) savedScrollTop = root.value.scrollTop;
}
onMounted(() => {
  root.value?.addEventListener('scroll', handleScroll, { passive: true });
});
onBeforeUnmount(() => {
  root.value?.removeEventListener('scroll', handleScroll);
});
onActivated(() => {
  nextTick(() => {
    if (root.value) root.value.scrollTop = savedScrollTop;
  });
});
</script>

<style scoped>
.IndexTablePane {
  height: 100%;
  overflow-y: auto;
  overscroll-behavior: contain;
  /* No bottom padding here: RecordTable's own root already pads for the
   * floating nav (--nav-clearance); doubling it leaves dead space. */
  padding: 0 16px;
}
</style>
