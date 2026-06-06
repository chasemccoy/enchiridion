<template>
  <RambleDraftUrlCard
    v-if="fellBack"
    :url="url"
  />
  <div
    v-else
    class="RambleDraftTweetCard"
  >
    <template v-if="isFetching && !tweet">
      <div class="RambleDraftTweetCard__placeholder">Fetching tweet…</div>
    </template>
    <template v-else-if="tweet">
      <header class="RambleDraftTweetCard__header">
        <img
          v-if="tweet.user.profile_image_url_https"
          :src="tweet.user.profile_image_url_https"
          class="RambleDraftTweetCard__avatar"
          :class="{
            'RambleDraftTweetCard__avatar--square': tweet.user.profile_image_shape === 'Square',
          }"
          alt=""
        />
        <div class="RambleDraftTweetCard__identity">
          <div class="RambleDraftTweetCard__name">{{ tweet.user.name }}</div>
          <div class="RambleDraftTweetCard__handle">@{{ tweet.user.screen_name }}</div>
        </div>
        <UIcon
          name="i-lucide-twitter"
          class="RambleDraftTweetCard__brand"
        />
      </header>

      <p class="RambleDraftTweetCard__text">{{ tweet.text }}</p>

      <div
        v-if="photos.length > 0"
        class="RambleDraftTweetCard__media"
        :class="{ 'RambleDraftTweetCard__media--single': photos.length === 1 }"
      >
        <img
          v-for="photo in photos"
          :key="photo.url"
          :src="photo.url"
          class="RambleDraftTweetCard__photo"
          alt=""
        />
      </div>

      <div
        v-if="tweet.quoted_tweet"
        class="RambleDraftTweetCard__quote"
      >
        <div class="RambleDraftTweetCard__quoteHeader">
          <span class="RambleDraftTweetCard__name">{{ tweet.quoted_tweet.user.name }}</span>
          <span class="RambleDraftTweetCard__handle">@{{ tweet.quoted_tweet.user.screen_name }}</span>
        </div>
        <p class="RambleDraftTweetCard__quoteText">{{ tweet.quoted_tweet.text }}</p>
      </div>

      <footer
        v-if="createdAt"
        class="RambleDraftTweetCard__footer"
      >{{ createdAt }}</footer>
    </template>
  </div>
</template>

<script setup lang="ts">
import RambleDraftUrlCard from './RambleDraftUrlCard.vue';
import useTweet from '@app/composables/useTweet';
import { formatDate } from '@shared/lib/formatting';
import { computed, toRef } from 'vue';

const props = defineProps<{
  url: string;
}>();

const urlRef = toRef(props, 'url');
const { data: response, isFetching, isError } = useTweet(urlRef);

// The endpoint returns {data?, tombstone?, notFound?}.
const tweet = computed(() => response.value?.data ?? null);

// If the tweet endpoint can't give us a tweet (deleted, not found, rate-
// limited, syndication error), fall back to the generic OG preview so the
// user at least sees something useful for the URL.
const fellBack = computed(() => {
  if (isFetching.value) return false;
  if (tweet.value) return false;
  return Boolean(isError.value || response.value?.notFound || response.value?.tombstone);
});

const photos = computed(() => tweet.value?.photos ?? []);

const createdAt = computed(() => {
  if (!tweet.value) return null;
  try {
    return formatDate(tweet.value.created_at);
  } catch {
    return null;
  }
});
</script>

<style scoped>
.RambleDraftTweetCard {
  display: grid;
  gap: 8px;
  padding: 14px 16px;
  border: 0.5px solid var(--ui-border);
  border-radius: var(--radius-md, 8px);
  background-color: var(--ui-bg-elevated);
  font-family: var(--font-sans, sans-serif);
}

.RambleDraftTweetCard__placeholder {
  font-size: 0.85rem;
  color: var(--ui-text-dimmed);
}

.RambleDraftTweetCard__header {
  display: flex;
  align-items: center;
  gap: 10px;
}

.RambleDraftTweetCard__avatar {
  width: 36px;
  height: 36px;
  border-radius: 999px;
  object-fit: cover;
  flex: none;
  background-color: var(--ui-bg-accented);
}

.RambleDraftTweetCard__avatar--square {
  border-radius: var(--radius-sm, 6px);
}

.RambleDraftTweetCard__identity {
  display: grid;
  gap: 0;
  flex: 1 1 auto;
  min-width: 0;
}

.RambleDraftTweetCard__name {
  font-weight: 600;
  font-size: 0.875rem;
  color: var(--ui-text-highlighted);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.RambleDraftTweetCard__handle {
  font-size: 0.75rem;
  color: var(--ui-text-dimmed);
}

.RambleDraftTweetCard__brand {
  flex: none;
  width: 18px;
  height: 18px;
  color: var(--ui-text-dimmed);
}

.RambleDraftTweetCard__text {
  font-size: 0.95rem;
  line-height: 1.5;
  color: var(--ui-text);
  margin: 0;
  white-space: pre-wrap;
  word-break: break-word;
}

.RambleDraftTweetCard__media {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 4px;
  margin-top: 4px;
}

.RambleDraftTweetCard__media--single {
  grid-template-columns: 1fr;
}

.RambleDraftTweetCard__photo {
  width: 100%;
  border-radius: var(--radius-sm, 6px);
  object-fit: cover;
  background-color: var(--ui-bg-accented);
}

.RambleDraftTweetCard__quote {
  display: grid;
  gap: 4px;
  padding: 10px 12px;
  border: 0.5px solid var(--ui-border);
  border-radius: var(--radius-sm, 6px);
  background-color: var(--ui-bg);
}

.RambleDraftTweetCard__quoteHeader {
  display: flex;
  gap: 6px;
  align-items: baseline;
}

.RambleDraftTweetCard__quoteText {
  font-size: 0.875rem;
  line-height: 1.45;
  color: var(--ui-text);
  margin: 0;
  white-space: pre-wrap;
  word-break: break-word;
}

.RambleDraftTweetCard__footer {
  font-size: 0.7rem;
  color: var(--ui-text-dimmed);
  margin-top: 2px;
}
</style>
