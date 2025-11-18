import useApiClient from '@app/composables/useApiClient';
import { useMutation, useQuery, useQueryClient } from '@tanstack/vue-query';
import type {
  DeleteRecordAPIResponse,
  GetRecordAPIResponse,
  GetRecordBySlugAPIResponse,
  LinksForRecordAPIResponse,
  UpsertRecordAPIResponse,
} from '@db/queries/records';
import type { GetFamilyTreeAPIResponse } from '@db/queries/tree';
import { toValue, type MaybeRefOrGetter } from 'vue';
import type { DbId } from '@shared/types/api';
import type { RecordInsert } from '@db/schema';
import type { SimilarRecordsAPIResponse } from '@db/queries/similar-records';

type OptionalMaybeRef<T> = MaybeRefOrGetter<T | null>;

export default function useRecord() {
  const { fetch } = useApiClient();
  const queryClient = useQueryClient();

  function getRecord(id: OptionalMaybeRef<DbId>, enabled: MaybeRefOrGetter<boolean> = true) {
    return useQuery({
      queryKey: ['get-record', id],
      queryFn: () => fetch<GetRecordAPIResponse>(`/record/${toValue(id)}`),
      enabled,
    });
  }

  function getRecordBySlug(slug: OptionalMaybeRef<string>) {
    return useQuery({
      queryKey: ['get-record-by-slug', slug],
      queryFn: () => fetch<GetRecordBySlugAPIResponse>(`/record/slug/${toValue(slug)}`),
    });
  }

  function getRecordTree(id: OptionalMaybeRef<DbId>, enabled: MaybeRefOrGetter<boolean> = true) {
    return useQuery({
      queryKey: ['get-record-tree', id],
      queryFn: () => fetch<GetFamilyTreeAPIResponse>(`/record/${toValue(id)}/tree`),
      enabled,
    });
  }

  function getRecordLinks(id: OptionalMaybeRef<DbId>, enabled: MaybeRefOrGetter<boolean> = true) {
    return useQuery({
      queryKey: ['get-record-links', id],
      queryFn: () => fetch<LinksForRecordAPIResponse>(`/record/${toValue(id)}/links`),
      enabled,
    });
  }

  function getSimilarRecords(
    id: OptionalMaybeRef<DbId>,
    enabled: MaybeRefOrGetter<boolean> = true,
  ) {
    return useQuery({
      queryKey: ['get-similar-records', id],
      queryFn: () => fetch<SimilarRecordsAPIResponse>(`/record/${toValue(id)}/similar`),
      enabled,
    });
  }

  function upsertRecord() {
    return useMutation({
      mutationFn: (data: RecordInsert) =>
        fetch<UpsertRecordAPIResponse>(`/record`, {
          method: 'PUT',
          body: JSON.stringify(data),
        }),
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ['list-records'] });
      },
    });
  }

  function deleteRecord() {
    return useMutation({
      mutationFn: (id: number) =>
        fetch<DeleteRecordAPIResponse>(`/record/${id}`, {
          method: 'DELETE',
        }),
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ['list-records'] });
      },
    });
  }

  return {
    getRecord,
    getRecordBySlug,
    getRecordTree,
    getRecordLinks,
    getSimilarRecords,
    upsertRecord,
    deleteRecord,
  };
}
