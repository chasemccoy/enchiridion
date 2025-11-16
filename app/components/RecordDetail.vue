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

      <span
        v-if="modelValue.url"
        class="RecordDetail__bylineItem"
      >
        at
        <LinkWithFavicon
          v-if="modelValue.url"
          class="RecordDetail__linkWithFavicon"
          :modelValue="modelValue.url"
        />
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
        placeholder="Write something about this record"
        variant="none"
        :rows="1"
        autoresize
      />
    </UFormField>

    <div v-if="childrenWithContent && childrenWithContent.length > 0">
      <ul
        class="RecordDetail__children"
        :class="{
          'RecordDetail__children--singleChild': childrenWithContent.length === 1,
        }"
      >
        <li
          v-for="child in childrenWithContent"
          :key="child.id"
        >
          <RouterLink :to="`/${child.source.slug}`">
            <RecordLink
              class="RecordDetail__recordLink shadow-xs"
              linkDirection="incoming"
              :modelValue="child.sourceId"
              :truncate="false"
              @updatePredicate="(predicate) => handleUpdatePredicate(child, predicate)"
              @deleteLink="() => handleDeleteLink(child.id)"
            />
          </RouterLink>
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

      <UFieldGroup>
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
      </UFieldGroup>

      <UFieldGroup v-if="createdAt">
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
      </UFieldGroup>

      <UFieldGroup>
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
      </UFieldGroup>
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

    <div
      v-if="linksByPredicateName"
      class="RecordDetail__links"
      :class="{
        'RecordDetail__links--singleChild': Object.keys(linksByPredicateName).length === 1,
      }"
    >
      <div
        v-for="(linksForType, predicateName) in linksByPredicateName"
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
              @updatePredicate="
                (predicate) =>
                  linkData.link ? handleUpdatePredicate(linkData.link, predicate) : undefined
              "
              @deleteLink="() => handleDeleteLink(linkData.link.id)"
            />
          </li>
        </ul>
      </div>
    </div>

    <div
      v-if="similarRecords && similarRecords.length > 0"
      class="RecordDetail__linksSection"
    >
      <h2 class="RecordDetail__sectionTitle RecordDetail__linksSectionTitle">Similar records</h2>

      <ul class="RecordDetail__list">
        <li
          v-for="entry in similarRecords"
          :key="entry.record.id"
        >
          <RecordLink
            class="RecordDetail__recordLink shadow-xs"
            :modelValue="entry.record.id"
          />
        </li>
      </ul>
    </div>

    <BrowserFrame
      v-if="modelValue.url && modelValue.type !== 'concept'"
      :key="modelValue.url"
      :url="modelValue.url"
    />
  </div>
</template>

<script setup lang="ts">
import AttachmentGallery from '@app/components/AttachmentGallery.vue';
import BrowserFrame from '@app/components/BrowserFrame.vue';
import RelationshipSelect from '@app/components/RelationshipSelect.vue';
import RecordLink from '@app/components/RecordLink.vue';
import type { GetRecordBySlugAPIResponse, LinksForRecordAPIResponse } from '@db/queries/records';
import { capitalize, formatDate } from '@shared/lib/formatting';
import { computed, onBeforeUnmount } from 'vue';
import type { LinkInsert, LinkSelect, PredicateSelect } from '@db/schema';
import { getIconForRecordSource, getIconForRecordType } from '@app/utils';
import type { DbId } from '@shared/types/api';
import FileUploadButton from '@app/components/FileUploadButton.vue';
import TitleField from '@app/components/TitleField.vue';
import CombinedFields from '@app/components/CombinedFields.vue';
import LinkWithFavicon from '@app/components/LinkWithFavicon.vue';
import type { FindAllRelatedRecordsAPIResponse } from '@db/queries/related-records';
import type { SimilarRecordsAPIResponse } from '@db/queries/related';

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

const { links, relatedRecords, similarRecords } = defineProps<{
  links?: LinksForRecordAPIResponse;
  relatedRecords?: FindAllRelatedRecordsAPIResponse;
  similarRecords?: SimilarRecordsAPIResponse;
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

type OutgoingLink = NonNullable<typeof links>['outgoingLinks'][number];
type IncomingLink = NonNullable<typeof links>['incomingLinks'][number];
type Link = OutgoingLink | IncomingLink;

// VirtualLink represents a recursive relation without a real database link
// It includes all properties needed to render like a real link
type VirtualLink = Omit<
  OutgoingLink,
  'predicate' | 'predicateId' | 'recordCreatedAt' | 'recordUpdatedAt'
> & {
  predicate?: PredicateSelect;
};

type LinkWithDirection = {
  link: Link | VirtualLink;
  direction: 'incoming' | 'outgoing';
};

const getPredicateName = (link: Link, direction: 'incoming' | 'outgoing'): string => {
  if (direction === 'incoming' && link.predicate.inverse?.name) {
    return link.predicate.inverse.name;
  }
  return link.predicate.name;
};

const linksByPredicateName = computed(() => {
  if (!links) return {};

  const grouped: Record<string, Array<LinkWithDirection>> = {};

  const addRealLink = (link: Link, direction: 'incoming' | 'outgoing') => {
    // Skip containment links - handled separately
    if (link.predicate.type === 'containment') return;

    const predicateName = getPredicateName(link, direction);

    if (!grouped[predicateName]) {
      grouped[predicateName] = [];
    }
    grouped[predicateName]!.push({ link, direction });
  };

  links.outgoingLinks?.forEach((link) => addRealLink(link, 'outgoing'));
  links.incomingLinks?.forEach((link) => addRealLink(link, 'incoming'));

  if (relatedRecords && relatedRecords.length > 0 && modelValue.value) {
    const currentRecordId = modelValue.value.id;

    const relatedToPredicate = [
      ...(links.outgoingLinks ?? []),
      ...(links.incomingLinks ?? []),
    ].find((link) => link.predicate.slug === 'related_to')?.predicate;

    if (!relatedToPredicate)
      return Object.fromEntries(Object.entries(grouped).filter(([, links]) => links.length > 0));

    // Get record IDs that already have real links
    const recordsWithRealLinks = new Set<number>();
    const existingRelatedLinks = grouped['related to'] ?? [];

    for (const linkData of existingRelatedLinks) {
      const recordId =
        linkData.direction === 'outgoing' ? linkData.link.targetId : linkData.link.sourceId;
      recordsWithRealLinks.add(recordId);
    }

    // Create virtual links for records without real links
    const virtualLinks: Array<LinkWithDirection> = [];

    for (const { record } of relatedRecords) {
      if (!recordsWithRealLinks.has(record.id)) {
        const virtualLink: VirtualLink = {
          id: currentRecordId + record.id, // Generate unique ID
          sourceId: currentRecordId,
          targetId: record.id,
          notes: null,
          target: {
            title: record.title,
            slug: record.slug,
          },
        };
        virtualLinks.push({ link: virtualLink, direction: 'outgoing' });
      }
    }

    // Add virtual links to the related_to section
    if (virtualLinks.length > 0) {
      if (!grouped['related to']) {
        grouped['related to'] = [];
      }
      grouped['related to'].push(...virtualLinks);
    }
  }

  return Object.fromEntries(Object.entries(grouped).filter(([, links]) => links.length > 0));
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

function handleUpdatePredicate(link: LinkSelect | VirtualLink, predicate: PredicateSelect) {
  emit('updatePredicate', {
    link: link as LinkSelect,
    predicate: predicate,
  });
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
  flex-wrap: wrap;
}

.RecordDetail__bylineItem {
  display: flex;
  align-items: center;
  color: var(--ui-text-muted);
  font-size: 0.8rem;
}

:deep(.RecordDetail__bylineButton) {
  max-width: 250px;
  margin-inline: -2px;

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

:deep(.RecordDetail__linkWithFavicon) {
  margin-inline: 0.75em;
}

.RecordDetail__content {
  margin-inline: -12px;
}

.RecordDetail__children:not(.RecordDetail__children--singleChild) {
  columns: 300px auto;
  gap: 8px;

  & > * + * {
    margin-top: 8px;
  }
}

.RecordDetail__links {
  margin-top: 16px;
}

.RecordDetail__links:not(.RecordDetail__links--singleChild) {
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
  column-gap: 2px;
  columns: 300px auto;

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
  break-inside: avoid;
}
</style>
