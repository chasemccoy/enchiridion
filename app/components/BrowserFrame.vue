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
  border-radius: 50%;
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
  background-color: white;
  border-radius: 6px;
  padding: 6px 8px;
  min-width: 0;
  flex: 1;
}

.BrowserFrame__url {
  font-size: 0.8rem;
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
</style>
