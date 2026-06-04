<template>
  <span class="ParentRefChip">
    <span class="ParentRefChip__iconWrap">
      <UIcon
        name="i-lucide-corner-down-right"
        class="ParentRefChip__icon"
      />
    </span>
    <span class="ParentRefChip__text">
      <RouterLink
        class="ParentRefChip__title"
        :to="`/${parent.slug}`"
      >{{ parent.title ?? parent.slug }}</RouterLink><template v-if="parentCreator"
        ><span class="ParentRefChip__creator"> by <RouterLink :to="`/${parentCreator.slug}`">{{ parentCreator.title }}</RouterLink></span></template>
    </span>
  </span>
</template>

<script setup lang="ts">
/**
 * Small inset chip pointing at a record's parent (contained_by / quotes target).
 *
 * Used in two places:
 *   - `RecordCard` on the search page, where every card with a parent shows
 *     it (so a highlight hit knows which book/article it came from).
 *   - `RecordLink` on record-detail pages, but only when the link itself has
 *     no title. Titled links don't need the extra context.
 *
 * The chip lazily fetches the parent record so it can show the parent's
 * creator alongside the title. TanStack Query caches per parent id, so
 * multiple chips on the same page (siblings under the same parent) share
 * one network request.
 */
import useRecord from '@app/composables/useRecord';
import { computed } from 'vue';

const { parent } = defineProps<{
  parent: { id: number; title: string | null; slug: string };
}>();

const { getRecord } = useRecord();
const parentId = computed(() => parent.id);
const { data: parentRecord } = getRecord(parentId);

const parentCreator = computed(() => {
  return (
    parentRecord.value?.outgoingLinks?.find((link) => link.predicate === 'created_by')?.target ??
    null
  );
});
</script>

<style scoped>
.ParentRefChip {
  display: inline-flex;
  align-items: flex-start;
  gap: 6px;
  padding: 6px 12px 6px 8px;
  border-radius: var(--radius-md);
  background-color: var(--ui-bg-elevated);
  color: var(--ui-text-muted);
  font-size: 0.75rem;
  font-weight: 500;
  line-height: 1.2;
  max-width: 100%;
}

/* Wrapper height = text line-height so the icon stays centred on the FIRST
 * line of the title/creator text, even when the text wraps to multiple lines. */
.ParentRefChip__iconWrap {
  flex: none;
  display: inline-flex;
  align-items: center;
  height: 1.2em;
}

.ParentRefChip__icon {
  width: 12px;
  height: 12px;
  color: var(--ui-text-dimmed);
}

/* Title and creator share a single inline text run so the creator, when it
 * wraps, lines up under the title rather than under the icon. */
.ParentRefChip__text {
  min-width: 0;
  flex: 1 1 auto;
}

.ParentRefChip__title {
  color: var(--ui-text-muted);

  &:hover {
    color: var(--ui-text);
    text-decoration: underline;
  }
}

.ParentRefChip__creator {
  color: var(--ui-text-dimmed);
  font-weight: 400;

  & a {
    color: var(--ui-text-muted);
    font-weight: 500;

    &:hover {
      color: var(--ui-text);
      text-decoration: underline;
    }
  }
}
</style>
