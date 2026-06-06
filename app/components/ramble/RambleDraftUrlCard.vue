<template>
  <div class="RambleDraftUrlCard">
    <template v-if="isFetching && !metadata">
      <div class="RambleDraftUrlCard__title RambleDraftUrlCard__title--pending">
        Fetching preview…
      </div>
    </template>
    <template v-else-if="metadata">
      <img
        v-if="metadata.image"
        :src="metadata.image"
        class="RambleDraftUrlCard__image"
        alt=""
      />
      <div class="RambleDraftUrlCard__body">
        <div
          v-if="metadata.siteName"
          class="RambleDraftUrlCard__site"
        >{{ metadata.siteName }}</div>
        <div class="RambleDraftUrlCard__title">
          {{ metadata.title || url }}
        </div>
        <p
          v-if="metadata.description"
          class="RambleDraftUrlCard__description"
        >{{ metadata.description }}</p>
      </div>
    </template>
    <template v-else>
      <div class="RambleDraftUrlCard__title RambleDraftUrlCard__title--pending">
        Couldn't fetch preview.
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
import useUrlMetadata from '@app/composables/useUrlMetadata';
import { toRef } from 'vue';

const props = defineProps<{
  url: string;
}>();

const urlRef = toRef(props, 'url');
const { data: metadata, isFetching } = useUrlMetadata(urlRef);
</script>

<style scoped>
.RambleDraftUrlCard {
  display: flex;
  gap: 12px;
  padding: 12px;
  border: 0.5px solid var(--ui-border);
  border-radius: var(--radius-md, 8px);
  background-color: var(--ui-bg-elevated);
  overflow: hidden;
}

.RambleDraftUrlCard__image {
  width: 96px;
  height: 96px;
  object-fit: cover;
  border-radius: var(--radius-sm, 6px);
  flex: none;
}

.RambleDraftUrlCard__body {
  display: grid;
  gap: 2px;
  min-width: 0;
}

.RambleDraftUrlCard__site {
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--ui-text-dimmed);
}

.RambleDraftUrlCard__title {
  font-weight: 500;
  font-size: 0.95rem;
  color: var(--ui-text-highlighted);
  overflow: hidden;
  text-overflow: ellipsis;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
}

.RambleDraftUrlCard__title--pending {
  color: var(--ui-text-dimmed);
  font-weight: 400;
  font-size: 0.85rem;
}

.RambleDraftUrlCard__description {
  font-size: 0.825rem;
  color: var(--ui-text-muted);
  margin: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  display: -webkit-box;
  -webkit-line-clamp: 3;
  -webkit-box-orient: vertical;
}
</style>
