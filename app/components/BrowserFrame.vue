<template>
  <div class="BrowserFrame">
    <div class="BrowserFrame__chrome">
      <div class="BrowserFrame__trafficLights">
        <div class="BrowserFrame__trafficLight BrowserFrame__trafficLight--close"></div>
        <div class="BrowserFrame__trafficLight BrowserFrame__trafficLight--minimize"></div>
        <div class="BrowserFrame__trafficLight BrowserFrame__trafficLight--maximize"></div>
      </div>

      <div class="BrowserFrame__urlBar">
        <span class="BrowserFrame__url">{{ displayUrl }}</span>
      </div>

      <div class="BrowserFrame__actions">
        <UBadge
          v-if="isArchived"
          color="neutral"
          variant="outline"
          class="BrowserFrame__archivedBadge"
          icon="i-lucide-archive"
          :label="archivedLabel"
        />
        <UTooltip
          v-if="isArchived"
          text="Open archived copy in a new tab"
        >
          <UButton
            color="neutral"
            variant="ghost"
            size="sm"
            icon="i-lucide-external-link"
            aria-label="Open archived copy in a new tab"
            target="_blank"
            :to="archivedSrc"
          />
        </UTooltip>
        <UTooltip :text="isArchived ? 'Re-archive this page' : 'Save a local offline copy'">
          <UButton
            color="neutral"
            variant="ghost"
            size="sm"
            :icon="isArchived ? 'i-lucide-rotate-cw' : 'i-lucide-archive'"
            :label="isArchiving ? 'Archiving…' : isArchived ? undefined : 'Archive'"
            :loading="isArchiving"
            :aria-label="isArchived ? 'Re-archive this page' : 'Archive this page'"
            @click="runArchive"
          />
        </UTooltip>
      </div>
    </div>

    <iframe
      v-if="isArchived"
      class="BrowserFrame__iframe"
      loading="lazy"
      sandbox=""
      :src="archivedSrc"
    />
    <iframe
      v-else-if="showLiveFrame"
      class="BrowserFrame__iframe"
      loading="lazy"
      :src="url"
    />
    <div
      v-else
      class="BrowserFrame__placeholder"
    >
      <UIcon
        name="i-lucide-archive"
        class="BrowserFrame__placeholderIcon"
      />
      <p class="BrowserFrame__placeholderText">
        This page can't be previewed live. Archive it to keep a permanent, previewable copy.
      </p>
    </div>

    <p
      v-if="archive?.status === 'failed'"
      class="BrowserFrame__error"
    >
      Archiving failed{{ archive.error ? `: ${archive.error}` : '' }}
    </p>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { formatDate } from '@shared/lib/formatting';
import useArchive from '@app/composables/useArchive';
import type { ArchiveSelect } from '@db/schema';

const props = defineProps<{
  url: string;
  recordId: number;
  archive?: ArchiveSelect | null;
}>();

const { archiveRecord, archiveSrc } = useArchive();
const { mutate, isPending } = archiveRecord();

function runArchive() {
  mutate(props.recordId);
}

// A stored copy exists — independent of the latest run's status, so a failed
// or in-flight re-archive keeps the last good copy visible.
const isArchived = computed(() => !!props.archive?.path);

// Covers both halves of a run: the mutation round-trip (isPending) and the
// server-side 'pending' row the record polls while the capture finishes.
const isArchiving = computed(() => isPending.value || props.archive?.status === 'pending');

const archivedSrc = computed(() => archiveSrc(props.archive) ?? undefined);

const archivedLabel = computed(() => {
  if (!props.archive?.archivedAt) return 'Archived';
  return `Archived on ${formatDate(props.archive.archivedAt)}`;
});

const displayUrl = computed(() => {
  try {
    return new URL(props.url).hostname;
  } catch {
    return props.url;
  }
});

// Sites known to refuse framing (X-Frame-Options / CSP frame-ancestors). This
// now only gates the *live-URL* fallback — an archived copy is served from our
// own origin, so it's always frameable regardless of host. Archiving one of
// these is the way to get a preview at all.
const BLOCKED_HOSTS = ['readwise', 'github', 'twitter', 'notion', 'medium'];

const isSupportedUrl = computed(() => {
  let host: string;
  try {
    host = new URL(props.url).hostname.toLowerCase();
  } catch {
    return false;
  }
  return !BLOCKED_HOSTS.some((blocked) => host.includes(blocked));
});

const showLiveFrame = computed(() => !isArchived.value && isSupportedUrl.value);
</script>

<style scoped>
.BrowserFrame {
  border-radius: var(--radius-lg);
  background-color: var(--ui-bg-elevated);
  padding: 8px;
  overflow: hidden;
}

/* Dark mode: use the app toolbar's darker chrome tone rather than the lighter
 * elevated surface. */
:global(.dark .BrowserFrame) {
  background-color: var(--index-chrome);
}

.BrowserFrame__chrome {
  display: flex;
  align-items: center;
  padding: 0 0 8px 8px;
  gap: 12px;
}

.BrowserFrame__trafficLights {
  display: flex;
  gap: 6px;
}

.BrowserFrame__trafficLight {
  width: 12px;
  height: 12px;
  border-radius: 999px;
  corner-shape: unset;
  position: relative;
}

.BrowserFrame__trafficLight--close {
  background-color: #ff5f57;
}

.BrowserFrame__trafficLight--minimize {
  background-color: #ffbd2e;
}

.BrowserFrame__trafficLight--maximize {
  background-color: #28ca42;
}

.BrowserFrame__urlBar {
  display: flex;
  align-items: center;
  /* `--ui-bg` is the page surface — lighter than the surrounding `--ui-bg-
   * elevated` chrome in light mode (white on gray) and darker than it in dark
   * mode (deep gray on slightly-lighter chrome), so we keep the recessed
   * look in both themes. */
  background-color: var(--ui-bg);
  border: 0.5px solid var(--ui-border);
  border-radius: 6px;
  padding: 4px 8px;
  min-width: 0;
  flex: 1;
}

.BrowserFrame__url {
  font-size: 0.8rem;
  line-height: 1.5;
  color: var(--ui-text);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  min-width: 0;
  user-select: all;
}

.BrowserFrame__actions {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
  /* Tighten just the URL-bar→actions gap (chrome gap is 12px) without affecting
   * the traffic-lights→URL-bar gap. */
  margin-left: -2px;
}

/* Match the record metadata badges (RecordDetail__badge): shrink the leading
 * icon to 12px and mute it, rather than UBadge's default ~16px. */
.BrowserFrame__archivedBadge {
  /* One-off: match the URL pill's exact height. Same font-size, line-height and
   * vertical padding, plus a transparent 0.5px border to mirror the pill's
   * border-box (the badge's own edge is a box-shadow, not a layout border). */
  font-size: 0.8rem;
  line-height: 1.5;
  padding: 4px 7px;
  border: 0.5px solid transparent;

  & :deep(svg) {
    width: 12px;
    height: 12px;
    color: var(--ui-text-muted);
  }
}

.BrowserFrame__iframe {
  aspect-ratio: 16/9;
  width: 100%;
  border: none;
  display: block;
  border-radius: var(--radius-md);
}

.BrowserFrame__placeholder {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  min-height: 200px;
  padding: 24px;
  text-align: center;
  border-radius: var(--radius-md);
  background-color: var(--ui-bg);
  color: var(--ui-text-muted);
}

.BrowserFrame__placeholderIcon {
  width: 24px;
  height: 24px;
  opacity: 0.6;
}

.BrowserFrame__placeholderText {
  font-size: 0.85rem;
  max-width: 40ch;
}

.BrowserFrame__error {
  margin-top: 8px;
  padding: 0 8px;
  font-size: 0.8rem;
  color: var(--ui-error, #ef4444);
}

/* On phones the 16:9 frame can dominate the viewport (and exceed it in
 * landscape). Cap its height so the surrounding record stays scrollable. */
@media (max-width: 768px) {
  .BrowserFrame__iframe {
    max-height: 50vh;
  }
}
</style>
