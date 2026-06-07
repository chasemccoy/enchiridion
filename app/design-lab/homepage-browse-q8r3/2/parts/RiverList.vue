<template>
  <div
    class="river"
    :class="{ 'river--compact': compact }"
  >
    <template v-if="grouped">
      <section
        v-for="group in groups"
        :key="group.label"
        class="river__group"
      >
        <div class="river__monthHead">
          <span class="river__month">{{ group.label }}</span>
          <span class="river__monthCount">{{ group.records.length }}</span>
          <span class="river__monthRule" />
        </div>
        <button
          v-for="r in group.records"
          :key="r.id"
          type="button"
          class="river__row"
          :class="{ 'river__row--active': r.slug === selectedSlug }"
          @click="$emit('select', r.slug)"
        >
          <Row
            :record="r"
            :compact="compact"
          />
        </button>
      </section>
    </template>

    <template v-else>
      <button
        v-for="r in records"
        :key="r.id"
        type="button"
        class="river__row"
        :class="{ 'river__row--active': r.slug === selectedSlug }"
        @click="$emit('select', r.slug)"
      >
        <Row
          :record="r"
          :compact="compact"
        />
      </button>
    </template>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import type { LabRecord } from '../../useLabRecords';
import Row from './RiverRow.vue';

defineEmits<{ select: [slug: string] }>();

const props = defineProps<{
  records: LabRecord[];
  selectedSlug?: string | null;
  compact?: boolean;
  grouped?: boolean;
}>();

const groups = computed(() => {
  const out: { label: string; records: LabRecord[] }[] = [];
  const index = new Map<string, LabRecord[]>();
  for (const r of props.records) {
    if (!r.recordCreatedAt) continue;
    const label = new Date(r.recordCreatedAt + 'Z').toLocaleDateString('en-US', {
      month: 'long',
      year: 'numeric',
    });
    if (!index.has(label)) {
      const bucket: LabRecord[] = [];
      index.set(label, bucket);
      out.push({ label, records: bucket });
    }
    index.get(label)!.push(r);
  }
  return out;
});
</script>

<style scoped>
.river {
  display: grid;
  gap: 0;
}
.river__monthHead {
  position: sticky;
  top: 0;
  z-index: 2;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 14px 0 7px;
  background: linear-gradient(var(--page-bg) 72%, transparent);
}
.river--compact .river__monthHead {
  background: linear-gradient(var(--ui-bg) 72%, transparent);
}
.river__month {
  font-size: 0.64rem;
  text-transform: uppercase;
  letter-spacing: 0.13em;
  font-weight: 600;
  color: var(--ui-text-muted);
}
.river__monthCount {
  font-size: 0.6rem;
  color: var(--ui-text-dimmed);
  font-variant-numeric: tabular-nums;
}
.river__monthRule {
  flex: 1;
  height: 1px;
  background: var(--ui-border);
}

.river__row {
  display: block;
  width: 100%;
  text-align: left;
  border: 0;
  background: transparent;
  cursor: pointer;
  padding: 0;
  border-radius: var(--radius-md);
  content-visibility: auto;
  contain-intrinsic-size: 0 38px;
}
.river__row:hover {
  background: var(--ui-bg);
}
.river--compact .river__row:hover {
  background: var(--ui-bg-elevated);
}
.river__row--active {
  background: var(--ui-bg);
  box-shadow: inset 0 0 0 1px var(--ui-border-accented);
}
.river--compact .river__row--active {
  background: var(--ui-bg-elevated);
  box-shadow: inset 2px 0 0 var(--ui-primary);
}
</style>
