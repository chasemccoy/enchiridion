<template>
  <div
    ref="elRef"
    class="SplitViewLayout"
    :class="{
      'SplitViewLayout--empty': isEmpty,
      'SplitViewLayout--detail': hasSelection,
    }"
  >
    <div
      ref="listRef"
      class="SplitViewLayout_list"
    >
      <div
        v-if="modelValue"
        class="SplitViewLayout_groups"
      >
        <div
          v-for="(group, groupKey) in groupedRecords"
          :key="groupKey"
          class="SplitViewLayout_group"
        >
          <h3
            v-if="grouped"
            class="SplitViewLayout_groupHeader"
          >
            {{ groupKey }}
            <template v-if="group.length > 4">({{ group.length }})</template>
          </h3>
          <ul class="SplitViewLayout_grid">
            <li
              v-for="{ record, index } in group"
              :key="record.id"
            >
              <RecordCard
                v-if="modelValue && modelValue[index]"
                v-model="modelValue[index]!"
                v-bind="getRecordCardProps(record)"
                :data-slug="record.slug"
                @vue:Mounted="handleRecordMounted(modelValue[index]!)"
              />
            </li>
          </ul>
        </div>

        <!-- Render an initial chunk, then grow as this sentinel scrolls into
          view. Keeps the first paint and filter toggles cheap (mounting ~80
          cards, not all ~500) without any windowing math. -->
        <div
          v-if="hasMoreToRender"
          ref="sentinel"
          class="SplitViewLayout_sentinel"
          aria-hidden="true"
        />
      </div>
    </div>

    <div
      v-if="!isEmpty"
      class="SplitViewLayout_detail"
    >
      <button
        v-if="hasSelection && listRoutePath"
        type="button"
        class="SplitViewLayout_back"
        @click="goBackToList"
      >
        <UIcon
          name="i-lucide-arrow-left"
          class="SplitViewLayout_backIcon"
        />
        All records
      </button>

      <slot />
    </div>
  </div>
</template>

<script setup lang="ts">
import RecordCard from '@app/components/RecordCard.vue';
import type { ListRecordsAPIResponse } from '@db/queries/records';
import { useIntersectionObserver } from '@vueuse/core';
import {
  computed,
  nextTick,
  onActivated,
  onBeforeUnmount,
  onMounted,
  ref,
  useTemplateRef,
  watch,
} from 'vue';
import { useRoute, useRouter } from 'vue-router';

const modelValue = defineModel<ListRecordsAPIResponse>();

const {
  isEmpty,
  recordCardProps,
  grouped = true,
} = defineProps<{
  isEmpty?: boolean;
  recordCardProps?: (record: ListRecordsAPIResponse[number]) => Record<string, string | boolean>;
  /** Group records under month/year headers. When false, renders one flat list
   * with no headers — used when the caller's sort (e.g. Title A–Z) doesn't line
   * up with chronological month grouping. */
  grouped?: boolean;
}>();

const elRef = useTemplateRef('elRef');
const listRef = useTemplateRef<HTMLDivElement>('listRef');
const route = useRoute();
const router = useRouter();

// A record detail is open when a child route is active. This (not the `isEmpty`
// prop, which means different things per view — "no selection" for the index but
// "the inbox is empty" for the inbox) is what drives the mobile single-column
// collapse, so the inbox's always-present detail pane doesn't blank the list at
// bare /inbox.
const hasSelection = computed(() => route.matched.length > 1);

// Route of the list behind the open detail (parent of the `:slug` child route:
// `/`, `/inbox`, `/v2`) — where the mobile back button returns to.
const listRoutePath = computed(() => {
  const parent = route.matched[route.matched.length - 2];
  return parent?.path ?? null;
});

function goBackToList() {
  if (listRoutePath.value) router.push(listRoutePath.value);
}

// --- Lazy rendering ----------------------------------------------------------
const CHUNK = 80;
const renderLimit = ref(CHUNK);
const totalCount = computed(() => modelValue.value?.length ?? 0);
const hasMoreToRender = computed(() => renderLimit.value < totalCount.value);

const sentinel = useTemplateRef<HTMLDivElement>('sentinel');
useIntersectionObserver(
  sentinel,
  ([entry]) => {
    if (entry?.isIntersecting) renderLimit.value += CHUNK;
  },
  { rootMargin: '600px' },
);

// When the list shrinks (a filter narrowed it), reset the window so re-widening
// the filter starts cheap again instead of re-rendering a previously-grown count.
watch(totalCount, (next, prev) => {
  if (next < prev) renderLimit.value = CHUNK;
});

// Keep a selected record (deep link / nav) inside the rendered window so
// scrollToSelectedRecord can find it even when it's far down the list.
function ensureSelectedRendered() {
  const slug = route.params.slug;
  if (!slug || !modelValue.value) return;
  const idx = modelValue.value.findIndex((record) => record.slug === slug);
  if (idx >= renderLimit.value) renderLimit.value = idx + CHUNK;
}

// Scroll preservation across KeepAlive cycles. The browser doesn't preserve
// scroll on internal scrollable containers when they're detached/reattached
// (which is what KeepAlive does). We can't read scrollTop in onDeactivated
// either — by then the element is already detached and reports 0 — so we
// track the latest scroll position continuously via a passive listener.
let savedScrollTop = 0;
function handleScroll() {
  if (listRef.value) savedScrollTop = listRef.value.scrollTop;
}
onMounted(() => {
  listRef.value?.addEventListener('scroll', handleScroll, { passive: true });
});
onBeforeUnmount(() => {
  listRef.value?.removeEventListener('scroll', handleScroll);
});
onActivated(() => {
  // Wait a frame so layout has settled before restoring; with
  // content-visibility: auto the scrollHeight expands as offscreen items
  // resolve, so an immediate set can get clamped. After restoring, run
  // scrollToSelectedRecord in case the route changed while we were cached
  // (e.g. a deep link to a different /record/X) — it's a no-op when the
  // selected card is already in view.
  ensureSelectedRendered();
  nextTick(() => {
    if (listRef.value) listRef.value.scrollTop = savedScrollTop;
    scrollToSelectedRecord();
  });
});

// Group records by month and year, including their original indices. Month
// groups appear in the order their first record shows up in `modelValue`, so the
// group order follows whatever sort the caller applied to the list (e.g. the v2
// index's newest/oldest toggle) rather than being pinned newest-first. Callers
// feed date-sorted data, so a date sort makes each month contiguous and the
// groups come out in that same date order.
const groupedRecords = computed(() => {
  if (!modelValue.value) return {};

  type RecordWithIndex = { record: ListRecordsAPIResponse[number]; index: number };

  // Only the first `renderLimit` records are rendered; the rest reveal as the
  // sentinel scrolls into view. Slicing from 0 keeps each record's original
  // index (used for the v-model binding below).
  const windowed = modelValue.value.slice(0, renderLimit.value);

  // Flat (ungrouped) mode: one bucket under an empty key, header hidden in the
  // template. Keeps every record — including those without a recordCreatedAt,
  // which the month-grouping path below skips.
  if (!grouped) {
    return {
      '': windowed.map((record, index) => ({ record, index })),
    } as Record<string, RecordWithIndex[]>;
  }

  const groups: Record<string, RecordWithIndex[]> = {};

  windowed.forEach((record, index) => {
    if (!record.recordCreatedAt) return;

    const date = new Date(record.recordCreatedAt + 'Z');
    const monthYear = date.toLocaleDateString('en-US', {
      month: 'long',
      year: 'numeric',
    });

    if (!groups[monthYear]) {
      groups[monthYear] = [];
    }

    groups[monthYear].push({ record, index });
  });

  return groups;
});

// Fires on selection change AND when the data/filter changes (modelValue), so a
// deep-linked or far-down record gets pulled into the render window before we
// try to scroll to it.
watch(
  [() => route.params.slug, modelValue],
  () => {
    ensureSelectedRendered();
    nextTick(scrollToSelectedRecord);
  },
  { flush: 'post', immediate: true },
);

function getRecordCardProps(record: ListRecordsAPIResponse[number]) {
  if (typeof recordCardProps === 'function') {
    return recordCardProps(record);
  }

  return recordCardProps || {};
}

function scrollToSelectedRecord() {
  if (!elRef.value) return;

  const selectedRecord = elRef.value.querySelector('[aria-current="page"]');
  if (!selectedRecord) return;

  // Only scroll when the record is actually off-screen: above the top
  // (rect.top < 0) or past the bottom (rect.bottom > viewport). A top of exactly
  // 0 is a valid, already-visible position — the previous `!rect.top` check
  // treated it as "needs scrolling" and caused a redundant jump.
  const rect = selectedRecord.getBoundingClientRect();
  if (rect.top < 0 || rect.bottom > window.innerHeight) {
    selectedRecord.scrollIntoView();
  }
}

function handleRecordMounted(record: ListRecordsAPIResponse[number]) {
  if (record.slug === route.params.slug) {
    scrollToSelectedRecord();
  }
}
</script>

<style scoped>
.SplitViewLayout {
  display: grid;
  grid-template-columns: minmax(400px, 0.35fr) 1fr;
  overflow-y: hidden;
  height: 100%;

  &.SplitViewLayout--empty {
    grid-template-columns: 1fr;
  }
}

.SplitViewLayout_list {
  height: 100%;
  overflow-x: hidden;
  overflow-y: auto;
  overscroll-behavior: contain;
  padding: 16px;
  /* Last cards must clear the floating nav pill + home indicator. */
  padding-bottom: var(--nav-clearance);
}

.SplitViewLayout:has(.SplitViewLayout_detail) .SplitViewLayout_list {
  padding-right: 1.2rem;
}

.SplitViewLayout_sentinel {
  height: 1px;
}

.SplitViewLayout_groups {
  display: grid;
  gap: 32px;
}

.SplitViewLayout_group {
  display: grid;
  gap: 8px;
  margin-top: -4px;
}

.SplitViewLayout_groupHeader {
  display: grid;
  grid-template-columns: 1fr auto 1fr;
  align-items: center;
  gap: 8px;
  font-size: 0.75rem;
  color: var(--ui-text-dimmed);

  &::before,
  &::after {
    content: '';
    height: 1px;
    background-color: var(--ui-border);
    display: block;
    width: 100%;
  }
}

.SplitViewLayout_grid {
  column-gap: 4px;

  & > * + * {
    margin-top: 6px;
  }

  .SplitViewLayout--empty & {
    columns: 30ch 3;

    & > * + * {
      margin-top: 4px;
    }
  }
}

.SplitViewLayout_detail {
  overflow-x: hidden;
  overflow-y: auto;
  overscroll-behavior: contain;
  /* Bottom padding clears the floating nav + home indicator so the last linked
   * records (whose edit/delete affordances live at the row's edge) stay
   * reachable. */
  padding: 2rem 2rem var(--nav-clearance) 1rem;
}

/* Mobile-only "back to list" button. The grid collapses to a single column on
 * narrow screens (master/detail), so this is the way back to the list once a
 * record fills the screen. Hidden on desktop, where the list is always visible
 * alongside. */
.SplitViewLayout_back {
  display: none;
}

.SplitViewLayout_backIcon {
  width: 16px;
  height: 16px;
}

@media (max-width: 768px) {
  /* Collapse to one column. With a detail open, hide the list so the record
   * gets the full width instead of being clipped into a sliver. */
  .SplitViewLayout {
    grid-template-columns: 1fr;
  }

  .SplitViewLayout--detail .SplitViewLayout_list {
    display: none;
  }

  /* With no record selected, suppress the detail pane entirely (the inbox keeps
   * an empty one mounted) so it doesn't leave dead space under the list. */
  .SplitViewLayout:not(.SplitViewLayout--detail) .SplitViewLayout_detail {
    display: none;
  }

  .SplitViewLayout_detail {
    padding: 0.5rem 1rem var(--nav-clearance);
  }

  .SplitViewLayout_back {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    margin-bottom: 12px;
    padding: 6px 10px 6px 6px;
    font-size: 0.85rem;
    color: var(--ui-text-muted);
    background-color: transparent;
    border: 0;
    cursor: pointer;
  }

  .SplitViewLayout_back:active {
    color: var(--ui-text);
  }
}
</style>
