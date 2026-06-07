<template>
  <div class="V23">
    <RecordHero />

    <section
      v-if="record"
      class="V23__links"
    >
      <header class="V23__sectionHead">
        <h2 class="V23__sectionTitle">Linked records</h2>
        <UButton
          size="xs"
          color="neutral"
          variant="ghost"
          icon="i-lucide-plus"
          label="New link"
        />
      </header>

      <RecordLinks
        v-if="linksWithoutTags"
        :links="linksWithoutTags"
        :currentRecordId="record.id"
      />
    </section>
  </div>
</template>

<script setup lang="ts">
import RecordHero from './RecordHero.vue';
import RecordLinks from '@app/components/RecordLinks.vue';
import { computed } from 'vue';
import { useLabRecord } from '../useLabRecord';

const { record, links } = useLabRecord();

// Tags surface in the hero already — drop them here so the section isn't
// "Tagged with: community, art, self-hosting" twice on the page.
const linksWithoutTags = computed(() => {
  if (!links.value) return undefined;
  return {
    ...links.value,
    outgoingLinks: (links.value.outgoingLinks ?? []).filter(
      (l) => l.predicate !== 'tagged_with',
    ),
    incomingLinks: (links.value.incomingLinks ?? []).filter(
      (l) => l.predicate !== 'tag_of',
    ),
  };
});
</script>

<style scoped>
.V23 {
  display: grid;
  gap: 24px;
  max-width: 820px;
  margin: 0 auto;
}

.V23__links {
  display: grid;
  gap: 12px;
  margin-top: 8px;
  padding-top: 20px;
  border-top: 1px solid var(--ui-border);
}

.V23__sectionHead {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
}

.V23__sectionTitle {
  font-size: 1rem;
  font-weight: 600;
}
</style>
