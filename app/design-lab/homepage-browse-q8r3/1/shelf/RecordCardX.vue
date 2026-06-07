<template>
  <RouterLink
    class="rcx"
    :to="`/${record.slug}`"
    :class="{ 'rcx--rediscover': rediscover }"
  >
    <div
      v-if="image"
      class="rcx__imageWrap"
    >
      <img
        class="rcx__image"
        loading="lazy"
        :src="image"
        :alt="record.title ?? ''"
      />
      <span class="rcx__typePill">
        <UIcon
          class="rcx__typeGlyph"
          :name="icon"
        />
      </span>
    </div>
    <div class="rcx__body">
      <p
        v-if="!image"
        class="rcx__kicker"
      >
        <UIcon
          class="rcx__kickerGlyph"
          :name="icon"
        />
        {{ capitalize(record.type) }}
      </p>
      <h3 class="rcx__title">{{ record.title }}</h3>
      <p
        v-if="preview"
        class="rcx__preview"
      >
        {{ preview }}
      </p>
      <p class="rcx__meta">
        <span v-if="host">{{ host }}</span>
        <span
          v-if="host"
          class="rcx__dot"
          >·</span
        >
        <span>{{ date }}</span>
      </p>
    </div>
  </RouterLink>
</template>

<script setup lang="ts">
import { getIconForRecordType } from '@app/utils';
import { capitalize, formatDate } from '@shared/lib/formatting';
import { computed } from 'vue';
import { firstImage, hostOf, plain, type LabRecord } from '../../useLabRecords';

const props = defineProps<{
  record: LabRecord;
  backend: string;
  rediscover?: boolean;
}>();

const image = computed(() => {
  const path = firstImage(props.record);
  return path ? `${props.backend}${path}` : null;
});
const icon = computed(() => getIconForRecordType(props.record.type));
const host = computed(() => hostOf(props.record));
const preview = computed(() => plain(props.record.summary || props.record.content));
const date = computed(() =>
  props.record.recordCreatedAt ? formatDate(props.record.recordCreatedAt, { year: false }) : '',
);
</script>

<style scoped>
.rcx {
  scroll-snap-align: start;
  flex: 0 0 auto;
  width: 248px;
  display: flex;
  flex-direction: column;
  border: 1px solid var(--ui-border);
  border-radius: var(--radius-lg);
  background: var(--ui-bg);
  overflow: hidden;
  transition:
    transform 0.14s ease,
    border-color 0.14s ease,
    box-shadow 0.14s ease;
}
.rcx:hover {
  transform: translateY(-3px);
  border-color: var(--ui-border-accented);
  box-shadow: 0 10px 26px -16px rgba(11, 11, 11, 0.4);
}
.rcx--rediscover {
  background: linear-gradient(180deg, color-mix(in srgb, var(--ui-warning) 7%, var(--ui-bg)), var(--ui-bg) 55%);
}

.rcx__imageWrap {
  position: relative;
  height: 132px;
}
.rcx__image {
  width: 100%;
  height: 100%;
  object-fit: cover;
  object-position: 50% 30%;
}
.rcx__typePill {
  position: absolute;
  top: 8px;
  left: 8px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  border-radius: 999px;
  background: color-mix(in srgb, var(--ui-bg) 80%, transparent);
  backdrop-filter: blur(6px);
  border: 1px solid var(--ui-border);
}
.rcx__typeGlyph {
  width: 13px;
  height: 13px;
  color: var(--ui-text-toned);
}

.rcx__body {
  display: grid;
  gap: 5px;
  padding: 12px 13px 14px;
  flex: 1;
  align-content: start;
}
.rcx__kicker {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 0.62rem;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  font-weight: 600;
  color: var(--ui-primary);
}
.rcx__kickerGlyph {
  width: 12px;
  height: 12px;
}
.rcx__title {
  font-size: 0.95rem;
  font-weight: 600;
  line-height: 1.25;
  color: var(--ui-text-highlighted);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.rcx__preview {
  font-size: 0.78rem;
  line-height: 1.4;
  color: var(--ui-text-muted);
  display: -webkit-box;
  -webkit-line-clamp: 3;
  line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.rcx__meta {
  margin-top: auto;
  padding-top: 4px;
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 0.68rem;
  color: var(--ui-text-dimmed);
}
.rcx__dot {
  opacity: 0.5;
}
</style>
