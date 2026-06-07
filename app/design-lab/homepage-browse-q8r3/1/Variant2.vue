<template>
  <div class="sh">
    <header class="sh__top">
      <div>
        <h1 class="sh__greeting">Your library</h1>
        <p class="sh__overview">
          <strong>{{ records.length }}</strong> records ·
          <strong>{{ byType.concept.length }}</strong> concepts ·
          <strong>{{ byType.entity.length }}</strong> sources &amp; people
        </p>
      </div>
      <UButton
        size="sm"
        color="neutral"
        variant="outline"
        icon="i-lucide-shuffle"
        label="Surprise me"
      />
    </header>

    <!-- Recently added -->
    <Shelf
      title="Recently added"
      hint="Fresh in your library"
      :count="titled.length"
    >
      <RecordCardX
        v-for="r in recent"
        :key="r.id"
        :record="r"
        :backend="backendBaseUrl"
      />
    </Shelf>

    <!-- Jump back in -->
    <Shelf
      title="Jump back in"
      hint="Older entries worth a second look"
      tone="rediscover"
    >
      <RecordCardX
        v-for="r in olderPicks"
        :key="r.id"
        :record="r"
        :backend="backendBaseUrl"
        rediscover
      />
    </Shelf>

    <!-- Concepts -->
    <Shelf
      title="Concepts to explore"
      hint="Themes that thread your notes together"
      :count="byType.concept.length"
    >
      <RouterLink
        v-for="t in concepts"
        :key="t.slug"
        class="sh__tile sh__tile--concept"
        :to="`/${t.slug}`"
      >
        <UIcon
          name="i-lucide-brain"
          class="sh__tileGlyph"
        />
        <span class="sh__tileTitle">{{ t.title }}</span>
        <span class="sh__tileMeta">{{ t.count }} linked</span>
      </RouterLink>
    </Shelf>

    <!-- People & sources -->
    <Shelf
      title="People &amp; sources"
      hint="Who and where your ideas come from"
      :count="byType.entity.length"
    >
      <RouterLink
        v-for="e in entities"
        :key="e.id"
        class="sh__tile sh__tile--entity"
        :to="`/${e.slug}`"
      >
        <UIcon
          name="i-lucide-users"
          class="sh__tileGlyph"
        />
        <span class="sh__tileTitle">{{ e.title }}</span>
        <span
          v-if="hostOf(e)"
          class="sh__tileMeta"
          >{{ hostOf(e) }}</span
        >
      </RouterLink>
    </Shelf>

    <!-- With media -->
    <Shelf
      title="With media"
      hint="Visual entries — images, captures, screenshots"
      :count="withImage.length"
    >
      <RecordCardX
        v-for="r in media"
        :key="r.id"
        :record="r"
        :backend="backendBaseUrl"
      />
    </Shelf>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { hostOf, useLabRecords } from '../useLabRecords';
import Shelf from './shelf/Shelf.vue';
import RecordCardX from './shelf/RecordCardX.vue';

const { records, titled, withImage, byType, topTags, olderPicks, backendBaseUrl } = useLabRecords();

const recent = computed(() => titled.value.slice(0, 16));
const media = computed(() => withImage.value.slice(0, 16));
const concepts = computed(() => topTags.value.filter((t) => t.type === 'concept').slice(0, 18));
const entities = computed(() => byType.value.entity.slice(0, 18));
</script>

<style scoped>
.sh {
  padding: 2rem 0 4rem;
  display: grid;
  gap: 2.25rem;
}

.sh__top {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 16px;
  padding: 0 2rem;
}
.sh__greeting {
  font-family: var(--font-serif);
  font-size: 2rem;
  font-weight: 600;
  letter-spacing: -0.02em;
  color: var(--ui-text-highlighted);
}
.sh__overview {
  margin-top: 4px;
  font-size: 0.9rem;
  color: var(--ui-text-muted);
}
.sh__overview strong {
  color: var(--ui-text-toned);
  font-weight: 600;
}

/* Tiles (concepts / entities) */
.sh__tile {
  scroll-snap-align: start;
  flex: 0 0 auto;
  width: 168px;
  height: 168px;
  display: grid;
  align-content: center;
  justify-items: start;
  gap: 8px;
  padding: 18px;
  border: 1px solid var(--ui-border);
  border-radius: var(--radius-lg);
  background: var(--ui-bg);
  transition:
    transform 0.14s ease,
    border-color 0.14s ease,
    box-shadow 0.14s ease;
}
.sh__tile:hover {
  transform: translateY(-3px);
  border-color: var(--ui-border-accented);
  box-shadow: 0 8px 24px -14px rgba(11, 11, 11, 0.35);
}
.sh__tile--concept {
  background: linear-gradient(160deg, var(--ui-bg) 0%, var(--ui-bg-elevated) 100%);
}
.sh__tileGlyph {
  width: 26px;
  height: 26px;
  color: var(--ui-primary);
}
.sh__tile--entity .sh__tileGlyph {
  color: var(--ui-text-muted);
}
.sh__tileTitle {
  font-size: 1rem;
  font-weight: 600;
  line-height: 1.2;
  color: var(--ui-text-highlighted);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.sh__tileMeta {
  font-size: 0.72rem;
  color: var(--ui-text-dimmed);
  text-transform: uppercase;
  letter-spacing: 0.04em;
}
</style>
