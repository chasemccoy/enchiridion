import useApiClient from '@app/composables/useApiClient';
import { useQuery } from '@tanstack/vue-query';
import { computed, toValue, type MaybeRef } from 'vue';

export type UrlMetadata = {
  url: string;
  finalUrl: string;
  title: string | null;
  description: string | null;
  image: string | null;
  siteName: string | null;
};

export default function useUrlMetadata(url: MaybeRef<string | null | undefined>) {
  const { fetch } = useApiClient();

  const enabled = computed(() => {
    const value = toValue(url);
    if (!value) return false;
    try {
      const parsed = new URL(value);
      return parsed.protocol === 'http:' || parsed.protocol === 'https:';
    } catch {
      return false;
    }
  });

  return useQuery({
    queryKey: ['url-metadata', url],
    queryFn: () => {
      const value = toValue(url) ?? '';
      const params = new URLSearchParams({ url: value });
      return fetch<UrlMetadata>(`/url-metadata?${params.toString()}`);
    },
    enabled,
    staleTime: 5 * 60 * 1000,
    // Bad URLs / unreachable hosts shouldn't trigger the default infinite retry.
    retry: 1,
  });
}
