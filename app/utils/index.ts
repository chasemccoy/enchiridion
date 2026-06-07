import { computed, type WritableComputedRef } from 'vue';
import type { EnrichedQuotedTweet, EnrichedTweet } from '@integrations/twitter/utils';
import { recordTypeEnum, type RecordType } from '@shared/types';
import type { PartialMediaInsert } from '@app/views/AddRecordView.vue';
import { type IntegrationType } from '@db/schema';

/** Type guard for a record type read from an untyped source (e.g. a URL query). */
export const isRecordType = (value: unknown): value is RecordType =>
  typeof value === 'string' && (recordTypeEnum as readonly string[]).includes(value);

/**
 * Drop the `score` field that semantic-search rows carry so the row matches the
 * plain record shape RecordCard/RecordTable expect.
 */
export function stripScore<T extends { score: number }>(row: T): Omit<T, 'score'> {
  const copy: Partial<T> = { ...row };
  delete copy.score;
  return copy as Omit<T, 'score'>;
}

/** True when a record has at least one attached media item. */
export const hasMedia = (record: { media?: unknown }): boolean =>
  Array.isArray(record.media) && record.media.length > 0;

/**
 * Structural ref-like — matches Ref<T>, ModelRef<T>, and WritableComputedRef<T>.
 */
type WritableRefLike<T> = { value: T };

/**
 * Adapts a `string | null` ref to `string | undefined` for nuxt-ui v-model
 * bindings. Reads null as undefined; writes undefined back as null.
 */
export function nullableStringModel(
  source: WritableRefLike<string | null | undefined>,
): WritableComputedRef<string | undefined> {
  return computed({
    get: () => source.value ?? undefined,
    set: (value) => {
      source.value = value ?? null;
    },
  });
}

/**
 * As nullableStringModel, but reads/writes one nullable string field of an
 * object held in a ref (or possibly-undefined ref, e.g. an async fetch
 * result). Uses spread to keep the parent ref reactive when the ref is a
 * Vue defineModel proxy. Writes are dropped when the underlying value is
 * undefined.
 */
export function nullableStringField<T extends Record<string, unknown>>(
  source: WritableRefLike<T | undefined>,
  key: keyof T & string,
): WritableComputedRef<string | undefined> {
  return computed({
    get: () => {
      const current = source.value;
      if (!current) return undefined;
      const value = current[key];
      return typeof value === 'string' ? value : undefined;
    },
    set: (value) => {
      const current = source.value;
      if (!current) return;
      source.value = { ...current, [key]: value ?? null };
    },
  });
}

export function getIconForRecordType(type: RecordType) {
  switch (type) {
    case 'artifact':
      return 'i-lucide-box';
    case 'concept':
      return 'i-lucide-brain';
    case 'entity':
      return 'i-lucide-users';
  }
}

export function getIconForRecordSource(source?: IntegrationType) {
  switch (source) {
    case 'twitter':
      return 'i-lucide-twitter';
    case 'readwise':
      return 'i-lucide-book-open';
    default:
      return undefined;
  }
}

export function getOriginOfUrl(urlString: string) {
  const url = new URL(urlString);
  return url.hostname.replace('www.', '');
}

const fetchMedia = async (url: string) => {
  const response = await fetch(url);
  const blob = await response.blob();
  const file = new File([blob], url, { type: blob.type });
  return file;
};

export async function mediaFileToDataURL(file: File): Promise<string | null> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();

    reader.onloadend = () => {
      if (!reader.result) return null;
      resolve(reader.result as string);
    };

    reader.onerror = (err) => reject(err);

    reader.readAsDataURL(file);
  });
}

export async function getImagesFromTweet(tweet: EnrichedTweet | EnrichedQuotedTweet) {
  const mediaDetails = tweet.mediaDetails;
  const images = [];
  const videos = [];

  for (const mediaDetail of mediaDetails ?? []) {
    if (mediaDetail.type === 'photo' && mediaDetail.media_url_https) {
      const file = await fetchMedia(mediaDetail.media_url_https);
      const dataURL = await mediaFileToDataURL(file);

      images.push({
        url: dataURL,
        width: mediaDetail.original_info.width,
        height: mediaDetail.original_info.height,
        file,
        type: 'image',
      } as PartialMediaInsert);
    }

    if (
      (mediaDetail.type === 'video' || mediaDetail.type === 'animated_gif') &&
      mediaDetail.video_info
    ) {
      const variants = mediaDetail.video_info.variants.filter(
        (variant) => variant.content_type === 'video/mp4',
      );
      const url = variants[variants.length - 1]!.url;
      const file = await fetchMedia(url);
      const dataURL = await mediaFileToDataURL(file);

      videos.push({
        url: dataURL,
        file,
        type: 'video',
      } as PartialMediaInsert);
    }
  }

  let other: PartialMediaInsert[] = [];

  if ('quoted_tweet' in tweet && tweet.quoted_tweet) {
    const quotedTweet = tweet.quoted_tweet;
    other = await getImagesFromTweet(quotedTweet);
  }

  if (tweet.card) {
    const values = tweet.card.binding_values;

    if (values && values.photo_image_full_size_original) {
      const image = values.photo_image_full_size_original.image_value;
      const file = await fetchMedia(image.url);
      const dataURL = await mediaFileToDataURL(file);

      images.push({
        url: dataURL,
        width: image.width,
        height: image.height,
        type: 'image',
        file,
      } as PartialMediaInsert);
    }
  }

  return [...images, ...videos, ...other];
}
