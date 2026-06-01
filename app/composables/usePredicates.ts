import useApiClient from '@app/composables/useApiClient';
import { useQuery } from '@tanstack/vue-query';
import type { GetPredicatesAPIResponse } from '@db/queries/links';

export default function usePredicates() {
  const { fetch } = useApiClient();

  function getPredicates() {
    return useQuery({
      queryKey: ['get-predicate-map'],
      queryFn: () => fetch<GetPredicatesAPIResponse>(`/predicates`),
    });
  }

  return {
    getPredicates,
  };
}
