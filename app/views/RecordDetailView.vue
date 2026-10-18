<template>
  <Head>
    <title v-if="record?.title">{{ record.title }} | Enchiridion</title>
  </Head>

  <template v-if="record">
    <ConceptDetail
      v-if="record.type === 'concept'"
      v-model="record"
      :links="links"
      :relatedRecords="relatedRecords"
      @fileDelete="handleMediaDelete"
      @createLink="handleCreateLink"
      @deleteLink="handleDeleteLink"
      @updatePredicate="handleUpdatePredicate"
    />
    <RecordDetail
      v-else
      v-model="record"
      :links="links"
      :relatedRecords="relatedRecords"
      :similarRecords="similarRecords"
      @fileUpload="handleFileUpload"
      @fileDelete="handleMediaDelete"
      @createLink="handleCreateLink"
      @deleteLink="handleDeleteLink"
      @updatePredicate="handleUpdatePredicate"
      @deleteRecord="handleDeleteRecord"
      @paste="handlePaste"
    />
  </template>
</template>

<script setup lang="ts">
import RecordDetail from '@app/components/RecordDetail.vue';
import useRecord from '@app/composables/useRecord';
import useMedia from '@app/composables/useMedia';
import { computed, onBeforeUnmount, onDeactivated, ref, toRaw, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { Head } from '@unhead/vue/components';
import type { GetRecordBySlugAPIResponse } from '@db/queries/records';
import { useQueryClient } from '@tanstack/vue-query';
import type { LinkInsert, LinkSelect, RecordInsert } from '@db/schema';
import type { Predicate, PredicateSlug } from '@shared/types';
import useLink from '@app/composables/useLink';
import type { DbId } from '@shared/types/api';
import useRelatedRecords from '@app/composables/useRelatedRecords';
import ConceptDetail from '@app/components/ConceptDetail.vue';

const router = useRouter();
const route = useRoute();
const toast = useToast();
const { getRecordBySlug, getRecordLinks, upsertRecord, deleteRecord, getSimilarRecords } =
  useRecord();
const { uploadMedia, deleteMedia, deleteMediaForRecord } = useMedia();
const { upsertLink, deleteLink } = useLink();

const record = ref<GetRecordBySlugAPIResponse | undefined>();

const recordSlug = computed(() => route.params.slug as string);
const { data, isError } = getRecordBySlug(recordSlug);

const recordId = computed(() => record.value?.id ?? null);
const isRecordFetched = computed(() => !!recordId.value);

const { data: links } = getRecordLinks(recordId, isRecordFetched);
const { data: similarRecords } = getSimilarRecords(recordId, isRecordFetched);

const { data: relatedRecords } = useRelatedRecords(recordSlug, isRecordFetched);

const { mutate: mutateRecord } = upsertRecord();
const { mutate: upsertLinkMutation } = upsertLink();
const { mutate: deleteLinkMutation } = deleteLink();

const { mutate: uploadMediaMutation } = uploadMedia();
const { mutate: deleteMediaMutation } = deleteMedia();
const { mutate: deleteMediaForRecordMutation } = deleteMediaForRecord();
const { mutate: deleteRecordMutation } = deleteRecord();

const queryClient = useQueryClient();

// Edits save a second after the last change (at most five seconds after the first), and a pending save always
// goes out before the page moves on: switching records, leaving the view or closing the tab sends it at once.
// A shared debounce used to swap a pending save for the next record's no-op one, losing the edit (a curate
// undone by opening another record within a second). Only real edits save: loading a record, or the server's
// answer, never writes it back.
const SAVE_DELAY = 1000;
const SAVE_MAX_WAIT = 5000;
let pending: { data: RecordInsert; slug: string } | null = null;
let timer: ReturnType<typeof setTimeout> | undefined;
let firstPendingAt = 0;
/** The record as last loaded or sent, serialized: a change matching it isn't an edit. */
let lastSynced: string | null = null;

function flushSave() {
  clearTimeout(timer);
  timer = undefined;
  if (!pending) return;
  const { data: body, slug } = pending;
  pending = null;
  mutateRecord(body, {
    onSuccess: (saved) => {
      // The cached copy shows what was saved, so coming back to the record never shows (or re-saves) the old one.
      queryClient.setQueryData<GetRecordBySlugAPIResponse>(['get-record-by-slug', slug], (old) =>
        old ? { ...old, ...saved } : old,
      );
    },
  });
}

function scheduleSave(data: RecordInsert, slug: string) {
  if (pending && pending.data.id !== data.id) flushSave();
  if (!pending) firstPendingAt = Date.now();
  pending = { data: structuredClone(toRaw(data)), slug };
  clearTimeout(timer);
  const wait = Math.min(SAVE_DELAY, Math.max(0, firstPendingAt + SAVE_MAX_WAIT - Date.now()));
  timer = setTimeout(flushSave, wait);
}

watch(recordSlug, flushSave);
onDeactivated(flushSave);
onBeforeUnmount(flushSave);
window.addEventListener('pagehide', flushSave);
onBeforeUnmount(() => window.removeEventListener('pagehide', flushSave));

watch(
  data,
  () => {
    if (!data.value) return;
    // Never over an edit still waiting to save: the server's copy is older than what's on screen.
    if (pending && pending.data.id === data.value.id) return;
    record.value = structuredClone(toRaw(data.value));
    lastSynced = JSON.stringify(record.value);
  },
  { immediate: true },
);

watch(
  record,
  () => {
    if (!record.value) return;
    const serialized = JSON.stringify(record.value);
    if (serialized === lastSynced) return;
    lastSynced = serialized;
    scheduleSave(record.value, recordSlug.value);
  },
  { deep: true },
);

watch(isError, () => {
  if (isError.value) {
    toast.add({
      title: 'Record not found',
      description: `Could not find a record for slug “${recordSlug.value}”`,
      color: 'error',
    });
  }
});

function handleFileUpload(file: File) {
  if (!recordId.value) return;

  uploadMediaMutation({
    file,
    recordId: recordId.value,
  });
}

function handlePaste(event: ClipboardEvent) {
  const data = event.clipboardData?.items;
  const items = Array.from(data ?? []);

  for (const item of items) {
    if (
      item.kind === 'file' &&
      (item.type.startsWith('image/') || item.type.startsWith('video/'))
    ) {
      const file = item.getAsFile();

      if (file) {
        event.preventDefault();
        handleFileUpload(file);
        return;
      }
    }
  }
}

function handleMediaDelete({ mediaId }: { mediaId?: number }) {
  if (!recordId.value || !mediaId) return;
  deleteMediaMutation(mediaId);
}

function handleCreateLink({ link }: { link: LinkInsert }) {
  upsertLinkMutation(link);
}

function handleDeleteLink({ linkId }: { linkId: DbId }) {
  deleteLinkMutation(linkId);
}

function handleUpdatePredicate({ link, predicate }: { link: LinkSelect; predicate: Predicate }) {
  upsertLinkMutation({
    ...link,
    predicate: predicate.slug as PredicateSlug,
  });
}

function handleDeleteRecord(id: DbId) {
  if (record.value?.media && record.value.media.length > 0) {
    deleteMediaForRecordMutation(id);
  }

  deleteRecordMutation(id, {
    onSuccess: (record) => {
      // Pop up to the parent list route (the index) when a detail child was
      // open, so the deleted record's now-dead URL doesn't linger. Carry the
      // query along — the index keeps all its toolbar state (filters, search,
      // view) there, and a bare path push would wipe it.
      const parentRoute = route.matched[route.matched.length - 2];
      if (route.matched.length > 1 && parentRoute) {
        router.push({ path: parentRoute.path, query: route.query });
      }

      toast.add({
        title: 'Record deleted',
        description: `The record with slug “${record[0]?.slug}” has been deleted.`,
        color: 'success',
      });
    },
  });
}
</script>
