<template>
  <div
    v-if="modelValue"
    class="RecordDetail"
  >
    <div class="RecordDetail__badges">
      <UBadge
        v-if="modelValue.isCurated !== true"
        color="neutral"
        variant="outline"
        class="RecordDetail__badge"
        icon="i-lucide-inbox"
        label="Needs curating"
      />

      <UBadge
        color="neutral"
        variant="outline"
        class="RecordDetail__badge"
        :icon="getIconForRecordType(modelValue.type)"
      >
        {{ capitalize(modelValue.type) }}
      </UBadge>

      <UBadge
        v-if="modelValue.source && modelValue.source !== 'manual'"
        color="neutral"
        variant="outline"
        class="RecordDetail__badge"
        :icon="getIconForRecordSource(modelValue.source)"
      >
        {{ capitalize(modelValue.source) }}
      </UBadge>

      <UBadge
        color="neutral"
        variant="outline"
        class="RecordDetail__badge"
        icon="i-lucide-calendar-arrow-down"
      >
        {{ capturedAt }}
      </UBadge>

      <UBadge
        v-if="modelValue"
        color="neutral"
        variant="outline"
        class="RecordDetail__badge"
        icon="i-lucide-hash"
      >
        {{ modelValue.id }}
      </UBadge>
    </div>

    <TitleField v-model="modelValue.title" />

    <div
      v-if="parent || creator"
      class="RecordDetail__byline"
    >
      <span
        v-if="parent"
        class="RecordDetail__bylineItem"
      >
        from
        <UButton
          icon="i-lucide-workflow"
          size="sm"
          color="neutral"
          variant="link"
          class="RecordDetail__bylineButton"
          :to="`/${parent.slug}`"
        >
          <span>{{ parent.title }}</span>
        </UButton>
      </span>

      <span
        v-if="creator"
        class="RecordDetail__bylineItem"
      >
        by
        <UButton
          icon="i-lucide-user-pen"
          size="sm"
          color="neutral"
          variant="link"
          class="RecordDetail__bylineButton"
          :to="`/${creator.slug}`"
        >
          <span>{{ creator.title }}</span>
        </UButton>
      </span>
    </div>

    <UFormField
      aria-label="Content"
      size="xs"
      class="RecordDetail__content"
    >
      <UTextarea
        v-model.trim="modelValue.content"
        size="xl"
        placeholder="Main content of the record"
        variant="none"
        :rows="1"
        autoresize
      />
    </UFormField>

    <div v-if="childrenWithContent && childrenWithContent.length > 0">
      <h2 class="RecordDetail__sectionTitle">Children</h2>

      <ul class="RecordDetail__children">
        <li
          v-for="child in childrenWithContent"
          :key="child.id"
        >
          <blockquote>
            {{ child.source.content }}
          </blockquote>
        </li>
      </ul>
    </div>

    <AttachmentGallery
      v-if="modelValue.media && modelValue.media.length > 0"
      v-model="modelValue.media"
      @fileUpload="(file) => emit('fileUpload', file)"
      @fileDelete="({ mediaId }) => emit('fileDelete', { mediaId })"
    />

    <CombinedFields>
      <UFormField
        aria-label="Summary"
        size="xs"
      >
        <UTextarea
          v-model.trim="modelValue.summary"
          size="lg"
          placeholder="A brief summary of this record"
          variant="outline"
          :rows="1"
          autoresize
        />
      </UFormField>

      <UButtonGroup>
        <UBadge
          color="neutral"
          variant="outline"
          size="lg"
          label="URL"
          class="RecordDetail__badge"
        />

        <UInput
          v-model="modelValue.url"
          class="RecordDetail__input"
          variant="outline"
          placeholder="example.com"
        >
          <template
            v-if="modelValue.url"
            #trailing
          >
            <UTooltip text="Open source URL">
              <UButton
                variant="link"
                size="sm"
                icon="i-lucide-external-link"
                aria-label="Open source URL"
                target="_blank"
                :to="modelValue.url"
              />
            </UTooltip>
          </template>
        </UInput>
      </UButtonGroup>

      <SlugField
        v-model="modelValue.slug"
        readonly
      />

      <UButtonGroup v-if="createdAt">
        <UBadge
          color="neutral"
          variant="outline"
          size="lg"
          label="Published"
          class="RecordDetail__badge"
        />

        <UInput
          v-model="createdAt"
          class="RecordDetail__input"
          variant="outline"
          placeholder="May 4, 1995"
          readonly
        />
      </UButtonGroup>

      <UButtonGroup>
        <UBadge
          color="neutral"
          variant="outline"
          size="lg"
          label="Notes"
          class="RecordDetail__badge"
        />

        <UTextarea
          v-model="modelValue.notes"
          class="RecordDetail__input"
          variant="outline"
          placeholder="Additional notes"
          :rows="1"
          autoresize
        />
      </UButtonGroup>
    </CombinedFields>

    <div class="RecordDetail__actions">
      <RelationshipSelect
        :sourceRecordId="modelValue.id"
        @createLink="handleCreateLink"
      />

      <FileUploadButton @fileUpload="(file) => emit('fileUpload', file)" />

      <UButton
        color="neutral"
        icon="i-lucide-trash"
        variant="subtle"
        label="Delete record"
        size="sm"
        @click="emit('deleteRecord', modelValue.id)"
      />

      <USwitch
        v-model="modelValue.isCurated"
        label="Curated"
        size="lg"
        class="RecordDetail__curatedSwitch"
      />
    </div>

    <div class="RecordDetail__links">
      <div
        v-for="(linksForType, predicateName) in linksByPredicateNameFiltered"
        :key="predicateName"
        class="RecordDetail__linksSection"
      >
        <h2 class="RecordDetail__sectionTitle RecordDetail__linksSectionTitle">
          {{ capitalize(String(predicateName)) }}
          <template v-if="linksForType.length > 3">({{ linksForType.length }})</template>
        </h2>

        <ul class="RecordDetail__list">
          <li
            v-for="linkData in linksForType"
            :key="linkData.link.id"
          >
            <RecordLink
              class="RecordDetail__recordLink shadow-xs"
              :modelValue="
                linkData.direction === 'outgoing' ? linkData.link.targetId : linkData.link.sourceId
              "
              :predicate="linkData.link.predicate"
              :linkDirection="linkData.direction"
              @updatePredicate="(predicate) => handleUpdatePredicate(linkData.link, predicate)"
              @deleteLink="() => handleDeleteLink(linkData.link.id)"
            />
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import AttachmentGallery from '@app/components/AttachmentGallery.vue';
import RelationshipSelect from '@app/components/RelationshipSelect.vue';
import RecordLink from '@app/components/RecordLink.vue';
import type { GetRecordBySlugAPIResponse, LinksForRecordAPIResponse } from '@db/queries/records';
import { capitalize, formatDate } from '@shared/lib/formatting';
import { computed, onBeforeUnmount, onMounted } from 'vue';
import type { LinkInsert, LinkSelect, PredicateSelect } from '@db/schema';
import { getIconForRecordSource, getIconForRecordType } from '@app/utils';
import type { DbId } from '@shared/types/api';
import SlugField from '@app/components/SlugField.vue';
import FileUploadButton from '@app/components/FileUploadButton.vue';
import TitleField from '@app/components/TitleField.vue';
import CombinedFields from '@app/components/CombinedFields.vue';

const modelValue = defineModel<GetRecordBySlugAPIResponse>({ required: true });

const emit = defineEmits<{
  fileUpload: [File];
  fileDelete: [{ mediaId?: number; url?: string }];
  createLink: [{ link: LinkInsert }];
  deleteLink: [{ linkId: DbId }];
  updatePredicate: [{ link: LinkSelect; predicate: PredicateSelect }];
  deleteRecord: [DbId];
  paste: [ClipboardEvent];
}>();

const { links } = defineProps<{
  links?: LinksForRecordAPIResponse;
}>();

const capturedAt = computed(() => {
  if (!modelValue.value) return null;
  return formatDate(modelValue.value.recordCreatedAt, { time: true });
});

const createdAt = computed(() => {
  if (!modelValue.value?.contentCreatedAt) return null;
  return formatDate(modelValue.value.contentCreatedAt);
});

const incomingLinks = computed(() => links?.incomingLinks ?? null);
const outgoingLinks = computed(() => links?.outgoingLinks ?? null);

const parent = computed(() => {
  if (!outgoingLinks.value) return null;

  return outgoingLinks.value.find((link) => link.predicate.type === 'containment')?.target ?? null;
});

const creator = computed(() => {
  if (!outgoingLinks.value) return null;

  return outgoingLinks.value.find((link) => link.predicate.slug === 'created_by')?.target ?? null;
});

const children = computed(() => {
  if (!incomingLinks.value) return null;

  return incomingLinks.value.filter((link) => link.predicate.type === 'containment');
});

const childrenWithContent = computed(() => {
  if (!children.value) return null;
  return children.value.filter((child) => child.source.content);
});

const linksByPredicateName = computed(() => {
  if (!links) return {};

  type Link =
    | NonNullable<typeof links>['outgoingLinks'][number]
    | NonNullable<typeof links>['incomingLinks'][number];

  type LinkWithDirection = {
    link: Link;
    direction: 'incoming' | 'outgoing';
  };

  const grouped: Record<string, Array<LinkWithDirection>> = {};

  const addLink = (link: Link, direction: 'incoming' | 'outgoing') => {
    let predicateName = link.predicate.name;

    if (direction === 'incoming' && link.predicate.inverseSlug) {
      if (link.predicate.inverse?.name) {
        predicateName = link.predicate.inverse.name;
      }
    }

    if (!grouped[predicateName]) {
      grouped[predicateName] = [];
    }

    grouped[predicateName].push({ link, direction });
  };

  links.outgoingLinks?.forEach((link) => addLink(link, 'outgoing'));
  links.incomingLinks?.forEach((link) => addLink(link, 'incoming'));

  return grouped;
});

const linksByPredicateNameFiltered = computed(() => {
  const grouped = linksByPredicateName.value;
  return Object.fromEntries(Object.entries(grouped).filter(([, links]) => links.length > 0));
});

onMounted(() => {
  document.addEventListener('paste', handlePaste);
});

onBeforeUnmount(() => {
  document.removeEventListener('paste', handlePaste);
});

function handlePaste(event: ClipboardEvent) {
  emit('paste', event);
}

function handleCreateLink(targetRecordId: DbId, predicateId: DbId) {
  if (!modelValue.value) return;

  emit('createLink', {
    link: {
      sourceId: modelValue.value.id,
      targetId: targetRecordId,
      predicateId,
    },
  });
}

function handleUpdatePredicate(link: LinkSelect, predicate: PredicateSelect) {
  emit('updatePredicate', { link, predicate });
}

function handleDeleteLink(linkId: DbId) {
  emit('deleteLink', { linkId });
}
</script>

<style scoped>
.RecordDetail {
  display: grid;
  gap: 1rem;
  max-width: 800px;
  margin: 0 auto;
}

.RecordDetail__badges {
  display: flex;
  gap: 4px;
  flex-wrap: wrap;
}

.RecordDetail__byline {
  display: inline-flex;
  margin-top: -12px;
}

.RecordDetail__bylineItem {
  display: flex;
  align-items: center;
  color: var(--ui-text-muted);
  font-size: 0.8rem;
}

:deep(.RecordDetail__bylineButton) {
  max-width: 250px;
  margin-left: -2px;

  &:hover {
    text-decoration: underline;
  }

  & :deep(span) {
    min-width: 0;
    text-overflow: ellipsis;
    overflow: hidden;
    white-space: nowrap;
  }
}

.RecordDetail__content {
  margin-inline: -12px;
}

.RecordDetail__children {
  font-size: 1rem;
  margin-top: 12px;

  & > * + * {
    border-top: 1px dashed var(--ui-border);
    padding-top: 16px;
    margin-top: 16px;
  }

  blockquote {
    padding-left: 20px;
    position: relative;
  }

  blockquote::before {
    content: '';
    width: 5px;
    height: 100%;
    background-color: var(--ui-border);
    position: absolute;
    top: 0;
    left: 0;
    border-radius: 8px;
  }
}

.RecordDetail__links {
  margin-top: 16px;
  columns: 300px auto;
}

.RecordDetail__section {
  display: grid;
  gap: 8px;
}

.RecordDetail__sectionTitle {
  font-size: 0.85rem;
  display: flex;
  align-items: center;
  gap: 0.25rem;
  color: var(--ui-text-dimmed);
  font-weight: 500;

  & :deep(svg) {
    width: 12px;
    height: 12px;
  }
}

.RecordDetail__badge {
  width: fit-content;

  & :deep(svg) {
    width: 12px;
    height: 12px;
    color: var(--ui-text-muted);
  }
}

.RecordDetail__list {
  li + li {
    margin-top: 2px;
  }
}

.RecordDetail__input {
  & :deep(input) {
    color: var(--ui-text-muted);
  }

  & :deep(input:hover),
  & :deep(input:focus) {
    color: var(--ui-text);
  }

  & :deep(svg) {
    width: 12px;
    height: 12px;
    color: var(--ui-text-muted);
  }
}

.RecordDetail__actions {
  display: flex;
  column-gap: 8px;
  row-gap: 12px;
  align-items: center;
  margin-bottom: -4px;
  flex-wrap: wrap;
}

.RecordDetail__curatedSwitch {
  margin-left: 4px;
}

.RecordDetail__linksSection {
  border-radius: var(--radius-xl);
  padding: 2px;
  break-inside: avoid;
  background-color: var(--ui-bg-elevated);

  & + & {
    margin-top: 16px;
  }
}

.RecordDetail__linksSectionTitle {
  padding: 4px 12px 6px;
}

.RecordDetail__recordLink {
  background-color: var(--ui-bg);
  border-radius: var(--radius-lg);
  padding: 8px 12px;
  border: 0.5px solid var(--ui-border);
}
</style>
