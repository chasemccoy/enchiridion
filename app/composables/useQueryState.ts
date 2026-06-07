import { useRoute, useRouter } from 'vue-router';

/**
 * URL-query state helpers shared by the record-list views (SearchView,
 * IndexV2View). Every piece of toolbar state lives in the query string so it
 * survives reloads, deep links, and back/forward.
 *
 * Reactivity: `readQuery` reads `route.query`, so calling it inside a `computed`
 * keeps that computed reactive to URL changes, exactly as an inline read would.
 */
export default function useQueryState() {
  const route = useRoute();
  const router = useRouter();

  /**
   * Read a single query param validated by `guard`, falling back when it's
   * absent or invalid. Repeated params (arrays) collapse to their first value.
   */
  function readQuery<T>(key: string, fallback: T, guard: (v: unknown) => v is T): T {
    const raw = route.query[key];
    const value = Array.isArray(raw) ? raw[0] : raw;
    return guard(value) ? value : fallback;
  }

  /**
   * Merge a patch into the query string via `router.replace`. Keys whose value
   * is `undefined` or `''` are removed so they drop out of the URL entirely.
   */
  function updateQuery(patch: Record<string, string | undefined>) {
    const next = { ...route.query };
    for (const [key, value] of Object.entries(patch)) {
      if (value === undefined || value === '') delete next[key];
      else next[key] = value;
    }
    router.replace({ query: next });
  }

  return { readQuery, updateQuery };
}
