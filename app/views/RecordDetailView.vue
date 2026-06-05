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
import { computed, ref, toRaw, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { Head } from '@unhead/vue/components';
import type { GetRecordBySlugAPIResponse } from '@db/queries/records';
import { useDebounceFn } from '@vueuse/core';
import type { LinkInsert, LinkSelect, RecordInsert } from '@db/schema';
import type { Predicate, PredicateSlug } from '@shared/types';
import useLink from '@app/composables/useLink';
import type { DbId } from '@shared/types/api';
import useRelatedRecords from '@app/composables/useRelatedRecords';
import ConceptDetail from '@app/components/ConceptDetail.vue';
import { RouteName } from '@app/router';

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

const debouncedMutate = useDebounceFn(
  (data: RecordInsert) => {
    mutateRecord(data);
  },
  1000,
  { maxWait: 5000 },
);

watch(
  data,
  () => {
    if (!data.value) return;
    record.value = structuredClone(toRaw(data.value));
  },
  { immediate: true },
);

watch(
  record,
  () => {
    if (!record.value) return;
    debouncedMutate(record.value);
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
      const parentRoute = route.matched[route.matched.length - 2];
      // Inbox owns its own post-delete navigation (advance to the next record
      // in the list). Other routes don't have that logic, so fall back to
      // popping up to the parent.
      if (
        route.matched.length > 1 &&
        parentRoute &&
        parentRoute.name !== RouteName.inbox
      ) {
        router.push(parentRoute.path);
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
