<template>
  <div class="RecordMetadataSheet">
    <div class="RecordMetadataSheet__row">
      <span class="RecordMetadataSheet__label">
        <UIcon
          class="RecordMetadataSheet__icon"
          name="i-lucide-text"
        />
        Summary
      </span>

      <UTextarea
        v-model.trim="summary"
        variant="none"
        class="RecordMetadataSheet__input"
        placeholder="A brief summary of this record"
        :rows="1"
        autoresize
      />
    </div>

    <div
      v-if="withSlug"
      class="RecordMetadataSheet__row"
    >
      <span class="RecordMetadataSheet__label">
        <UIcon
          class="RecordMetadataSheet__icon"
          name="i-lucide-hash"
        />
        Slug
      </span>

      <UInput
        v-model="slugProxy"
        variant="none"
        class="RecordMetadataSheet__input"
        placeholder="record-slug"
        required
      />
    </div>

    <div class="RecordMetadataSheet__row">
      <span class="RecordMetadataSheet__label">
        <UIcon
          class="RecordMetadataSheet__icon"
          name="i-lucide-link"
        />
        URL
      </span>

      <div class="RecordMetadataSheet__url">
        <UInput
          v-model="url"
          variant="none"
          class="RecordMetadataSheet__input"
          placeholder="example.com"
        />

        <UTooltip
          v-if="url"
          text="Open source URL"
        >
          <UButton
            class="RecordMetadataSheet__urlOpen"
            variant="ghost"
            color="neutral"
            size="xs"
            icon="i-lucide-external-link"
            aria-label="Open source URL"
            target="_blank"
            :to="url"
          />
        </UTooltip>
      </div>
    </div>

    <div
      v-if="published"
      class="RecordMetadataSheet__row"
    >
      <span class="RecordMetadataSheet__label">
        <UIcon
          class="RecordMetadataSheet__icon"
          name="i-lucide-calendar"
        />
        Published
      </span>

      <span class="RecordMetadataSheet__static">{{ published }}</span>
    </div>

    <div class="RecordMetadataSheet__row">
      <span class="RecordMetadataSheet__label">
        <UIcon
          class="RecordMetadataSheet__icon"
          name="i-lucide-pencil-line"
        />
        Notes
      </span>

      <UTextarea
        v-model="notes"
        variant="none"
        class="RecordMetadataSheet__input"
        placeholder="Additional notes"
        :rows="1"
        autoresize
      />
    </div>
  </div>
</template>

<script setup lang="ts">
// Shared metadata "property sheet" — labeled, hover-to-edit rows used by both
// the record detail view and the add-record form so the two stay in sync.
// Status/curation, attachments, and dates other than the publish date live
// outside this sheet by design.
import { slugify } from '@shared/lib/formatting';
import { computed } from 'vue';

const summary = defineModel<string | undefined>('summary');
const url = defineModel<string | undefined>('url');
const notes = defineModel<string | undefined>('notes');
const slug = defineModel<string>('slug', { default: '' });

const { published = null, withSlug = false } = defineProps<{
  /** Formatted publish date; the row is hidden when absent. */
  published?: string | null;
  /** Render an editable, auto-slugifying Slug row (add form only). */
  withSlug?: boolean;
}>();

// Slugify whatever is typed into the slug row.
const slugProxy = computed({
  get: () => slug.value,
  set: (value: string) => {
    slug.value = slugify(value);
  },
});
</script>

<style scoped>
.RecordMetadataSheet {
  display: grid;
}

.RecordMetadataSheet__row {
  display: grid;
  grid-template-columns: var(--metadata-sheet-label-width, 116px) 1fr;
  gap: var(--metadata-sheet-gap, 12px);
  align-items: start;
  padding: 3px 8px;
  margin-inline: -8px;
  border-radius: var(--radius-md);
  transition: background 0.1s ease;

  &:hover {
    background: var(--ui-bg-elevated);
  }
}

.RecordMetadataSheet__label {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 0.78rem;
  color: var(--ui-text-muted);
  padding-top: 7px;
}

.RecordMetadataSheet__icon {
  width: 13px;
  height: 13px;
  color: var(--ui-text-dimmed);
  flex-shrink: 0;
}

.RecordMetadataSheet__input {
  width: 100%;

  & :deep(input),
  & :deep(textarea) {
    font-size: 0.85rem;
    padding-inline: 0;
    color: var(--ui-text-muted);
  }

  & :deep(input:hover),
  & :deep(input:focus),
  & :deep(textarea:hover),
  & :deep(textarea:focus) {
    color: var(--ui-text);
  }
}

.RecordMetadataSheet__url {
  display: flex;
  align-items: center;
  gap: 4px;
}

.RecordMetadataSheet__urlOpen {
  opacity: 0;
  transition: opacity 0.12s ease;
}

.RecordMetadataSheet__row:hover .RecordMetadataSheet__urlOpen {
  opacity: 1;
}

/* Match the editable inputs' box (6px block padding + their line-height) so the
   read-only row is the same height as the others and its text aligns the same
   way against the label. */
.RecordMetadataSheet__static {
  font-size: 0.85rem;
  line-height: 1.4286;
  color: var(--ui-text-muted);
  padding-block: 6px;
}
</style>
