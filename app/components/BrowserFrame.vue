<template>
  <div
    v-if="isSupportedUrl"
    class="BrowserFrame"
  >
    <div class="BrowserFrame__chrome">
      <div class="BrowserFrame__trafficLights">
        <div class="BrowserFrame__trafficLight BrowserFrame__trafficLight--close"></div>
        <div class="BrowserFrame__trafficLight BrowserFrame__trafficLight--minimize"></div>
        <div class="BrowserFrame__trafficLight BrowserFrame__trafficLight--maximize"></div>
      </div>

      <div class="BrowserFrame__urlBar">
        <span class="BrowserFrame__url">{{ displayUrl }}</span>
      </div>
    </div>

    <iframe
      class="BrowserFrame__iframe"
      loading="lazy"
      :src="url"
    />
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';

const props = defineProps<{
  url: string;
}>();

const displayUrl = computed(() => {
  try {
    const url = new URL(props.url);
    return url.hostname;
  } catch {
    return props.url;
  }
});

// Sites known to refuse framing (X-Frame-Options / CSP frame-ancestors). Match
// is a hostname substring so subdomains like `gist.github.com` or `m.twitter.com`
// get caught too. Add more as you encounter them.
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
</script>

<style scoped>
.BrowserFrame {
  border-radius: var(--radius-lg);
  background-color: var(--ui-bg-elevated);
  padding: 8px;
  overflow: hidden;
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
  border-radius: 6px;
  padding: 6px 8px;
  min-width: 0;
  flex: 1;
}

.BrowserFrame__url {
  font-size: 0.8rem;
  color: var(--ui-text);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  min-width: 0;
  user-select: all;
}

.BrowserFrame__iframe {
  aspect-ratio: 16/9;
  width: 100%;
  border: none;
  display: block;
  border-radius: var(--radius-md);
}

/* On phones the 16:9 frame can dominate the viewport (and exceed it in
 * landscape). Cap its height so the surrounding record stays scrollable. */
@media (max-width: 768px) {
  .BrowserFrame__iframe {
    max-height: 50vh;
  }
}
</style>
