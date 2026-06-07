<template>
  <span
    class="row"
    :class="{ 'row--compact': compact }"
  >
    <UIcon
      class="row__glyph"
      :name="icon"
      :class="`row__glyph--${record.type}`"
    />
    <span class="row__main">
      <span class="row__title">{{ record.title }}</span>
      <span
        v-if="preview && !compact"
        class="row__preview"
        >{{ preview }}</span
      >
    </span>
    <template v-if="!compact">
      <span
        v-if="tags.length"
        class="row__tags"
      >
        <span
          v-for="t in tags.slice(0, 2)"
          :key="t!.slug"
          class="row__tag"
          >{{ t!.title }}</span
        >
      </span>
      <span
        v-if="host"
        class="row__host"
        >{{ host }}</span
      >
    </template>
    <span class="row__date">{{ date }}</span>
    <img
      v-if="thumb"
      class="row__thumb"
      loading="lazy"
      alt=""
      :src="thumb"
    />
    <span
      v-else
      class="row__thumb row__thumb--empty"
    />
  </span>
</template>

<script setup lang="ts">
import useApiClient from '@app/composables/useApiClient';
import { getIconForRecordType } from '@app/utils';
import { formatDate } from '@shared/lib/formatting';
import { computed } from 'vue';
import { firstImage, hostOf, plain, tagsOf, type LabRecord } from '../../useLabRecords';

const props = defineProps<{ record: LabRecord; compact?: boolean }>();
const { backendBaseUrl } = useApiClient();

const icon = computed(() => getIconForRecordType(props.record.type));
const host = computed(() => hostOf(props.record));
const tags = computed(() => tagsOf(props.record));
const preview = computed(() => plain(props.record.summary || props.record.content));
const date = computed(() =>
  props.record.recordCreatedAt ? formatDate(props.record.recordCreatedAt, { year: false }) : '',
);
const thumb = computed(() => {
  const path = firstImage(props.record);
  return path ? `${backendBaseUrl}${path}` : null;
});
</script>

<style scoped>
.row {
  display: grid;
  grid-template-columns: 18px minmax(0, 1fr) auto auto 3.2rem 28px;
  align-items: center;
  gap: 12px;
  padding: 7px 10px;
}
.row--compact {
  grid-template-columns: 16px minmax(0, 1fr) auto 24px;
  gap: 9px;
  padding: 7px 8px;
}
.row__glyph {
  width: 14px;
  height: 14px;
  color: var(--ui-text-dimmed);
}
.row__glyph--concept {
  color: var(--ui-primary);
}
.row__main {
  display: grid;
  grid-template-columns: minmax(0, auto) minmax(0, 1fr);
  align-items: baseline;
  gap: 10px;
  min-width: 0;
}
.row--compact .row__main {
  grid-template-columns: minmax(0, 1fr);
}
.row__title {
  font-size: 0.85rem;
  font-weight: 500;
  color: var(--ui-text-highlighted);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 42ch;
}
.row__preview {
  font-size: 0.78rem;
  color: var(--ui-text-dimmed);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  min-width: 0;
}
.row__tags {
  display: inline-flex;
  gap: 4px;
}
.row__tag {
  font-size: 0.64rem;
  color: var(--ui-text-muted);
  background: var(--ui-bg-elevated);
  border: 1px solid var(--ui-border-muted);
  padding: 1px 7px;
  border-radius: 999px;
  white-space: nowrap;
  max-width: 110px;
  overflow: hidden;
  text-overflow: ellipsis;
}
.row__host {
  font-size: 0.7rem;
  color: var(--ui-text-dimmed);
  white-space: nowrap;
  max-width: 130px;
  overflow: hidden;
  text-overflow: ellipsis;
  text-align: right;
}
.row__date {
  font-size: 0.7rem;
  color: var(--ui-text-dimmed);
  text-align: right;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
.row__thumb {
  width: 28px;
  height: 28px;
  object-fit: cover;
  border-radius: 5px;
  border: 1px solid var(--ui-border);
}
.row--compact .row__thumb {
  width: 24px;
  height: 24px;
}
.row__thumb--empty {
  border: 0;
  background: transparent;
}
</style>
