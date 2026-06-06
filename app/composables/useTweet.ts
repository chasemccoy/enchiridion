import useApiClient from '@app/composables/useApiClient';
import { extractTweetId } from '@app/lib/ramble/tweetUrl';
import type { FetchTweetAPIResponse } from '@api/twitter';
import { useQuery } from '@tanstack/vue-query';
import { computed, toValue, type MaybeRef } from 'vue';

/**
 * Fetch a tweet by URL or id. The query stays disabled until the input
 * yields a valid tweet id, so passing arbitrary URLs in is safe.
 */
export default function useTweet(input: MaybeRef<string | null | undefined>) {
  const { fetch } = useApiClient();

  const id = computed(() => {
    const value = toValue(input);
    if (!value) return null;
    return extractTweetId(value);
  });

  return useQuery({
    queryKey: ['tweet', id],
    queryFn: () => fetch<FetchTweetAPIResponse>(`/tweet/${id.value}`),
    enabled: computed(() => id.value !== null),
    staleTime: 10 * 60 * 1000,
    retry: 1,
  });
}
