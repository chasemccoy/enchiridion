<template>
  <Head>
    <title>New record | Enchiridion</title>
  </Head>

  <div class="AddRecordView">
    <AddRecordForm
      v-model="record"
      v-model:files="files"
      v-model:links="links"
      @save="handleSubmit"
    />
  </div>
</template>

<script setup lang="ts">
import AddRecordForm from '@app/components/AddRecordForm.vue';
import useApiClient from '@app/composables/useApiClient';
import useRecord from '@app/composables/useRecord';
import type { LinkInsert, MediaInsert, RecordInsert } from '@db/schema';
import { Head } from '@unhead/vue/components';
import { ref, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import type { FetchTweetAPIResponse } from '@api/twitter';
import { getImagesFromTweet } from '@app/utils';
import useMedia from '@app/composables/useMedia';
import { mapTweetToRecord } from '@integrations/twitter/records';
import useLink from '@app/composables/useLink';
import type { GetRecordBySlugAPIResponse } from '@db/queries/records';

export type PartialLinkInsert = Omit<LinkInsert, 'sourceId'>;
export type PartialMediaInsert = Omit<MediaInsert, 'recordId'> & {
  file?: File;
};

export type NewRecordData = {
  record: RecordInsert;
  links?: PartialLinkInsert[];
  files?: PartialMediaInsert[];
};

const router = useRouter();
const route = useRoute();
const toast = useToast();
const { fetch } = useApiClient();

const files = ref<PartialMediaInsert[]>([]);
const links = ref<PartialLinkInsert[]>([]);

const emptyRecord: RecordInsert = {
  type: 'artifact',
  title: '',
  slug: '',
  source: 'manual',
};

const record = ref<RecordInsert>(emptyRecord);

const { upsertRecord } = useRecord();
const { uploadMedia } = useMedia();
const { upsertLink } = useLink();
const { mutate: upsertLinkMutation } = upsertLink();
const { mutate: upsertRecordMutation } = upsertRecord();
const { mutate: uploadMediaMutation } = uploadMedia();

function handleSubmit(data: NewRecordData) {
  const { record, files = [], links = [] } = data;

  upsertRecordMutation(record, {
    onSuccess: (r) => {
      for (const file of files) {
        if (!file.file) continue;

        uploadMediaMutation({
          file: file.file,
          recordId: r.id,
        });
      }

      for (const link of links) {
        upsertLinkMutation({ sourceId: r.id, ...link });
      }

      router.push(`/${record.slug}`);
    },
    onError: (e) => {
      toast.add({
        title: 'Error',
        description: e.message.slice(0, 250),
        color: 'error',
        icon: 'i-lucide-circle-alert',
      });
    },
  });
}

onMounted(async () => {
  const query = route.query;

  let populatedRecord = { ...emptyRecord };

  if (query.tweet || (query.url && query.url.includes('https://x.com'))) {
    const tweet = query.tweet || query.url;
    if (!tweet || typeof tweet !== 'string') return;

    const tweetId = tweet.match(/\/status\/(\d+)/)?.[1];
    if (!tweetId) return;

    populatedRecord.source = 'twitter';
    populatedRecord.url = tweet;

    const {
      data: tweetDetails,
      notFound,
      tombstone,
    } = await fetch<FetchTweetAPIResponse>(`/tweet/${tweetId}`);

    if (notFound || tombstone || !tweetDetails) {
      toast.add({
        title: 'Failed to fetch tweet',
        description: `Couldn’t fetch tweet at ${tweet}`,
        color: 'error',
        icon: 'i-lucide-circle-alert',
      });

      return;
    }

    files.value = await getImagesFromTweet(tweetDetails);
    populatedRecord = mapTweetToRecord(tweetDetails);

    const tweetRecord = await fetch<GetRecordBySlugAPIResponse>('/record/slug/tweet');

    if (tweetRecord) {
      links.value.push({
        targetId: tweetRecord.id,
        predicate: 'has_format',
      });
    }
  }

  if (query.type && typeof query.type === 'string') {
    if (['entity', 'concept', 'artifact'].includes(query.type)) {
      populatedRecord.type = query.type as 'entity' | 'concept' | 'artifact';
    }
  }

  if (query.title && typeof query.title === 'string') {
    populatedRecord.title = query.title;
  }

  if (query.url && typeof query.url === 'string') {
    populatedRecord.url = query.url;
  }

  if (query.summary && typeof query.summary === 'string') {
    populatedRecord.summary = query.summary;
  }

  if (query.content && typeof query.content === 'string') {
    populatedRecord.content = query.content;
  }

  if (query.notes && typeof query.notes === 'string') {
    populatedRecord.notes = query.notes;
  }

  record.value = populatedRecord;
});
</script>

<style scoped>
.AddRecordView {
  background-color: var(--ui-bg);
  padding: 24px;
  max-width: 40em;
  margin: -16px;
  display: flex;
  flex-direction: column;
  min-height: 60dvh;

  @media (min-width: 600px) {
    border-radius: var(--radius-xl);
    border: 1px solid var(--ui-border);
    margin: auto;
    padding: 32px 40px 40px;
    width: 100%;
  }
}
</style>
