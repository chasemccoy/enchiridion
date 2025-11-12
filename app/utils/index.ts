import type { EnrichedQuotedTweet, EnrichedTweet } from '@integrations/twitter/utils';
import type { RecordType } from '@shared/types';
import type { PartialMediaInsert } from '@app/views/AddRecordView.vue';
import { type IntegrationType } from '@db/schema';

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
