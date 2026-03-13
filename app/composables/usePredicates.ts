import { ALL_PREDICATES, type Predicate } from '@shared/predicates';

export type { Predicate };

export default function usePredicates() {
  function getPredicates() {
    return {
      data: { value: ALL_PREDICATES as readonly Predicate[] },
    };
  }

  return {
    getPredicates,
  };
}
