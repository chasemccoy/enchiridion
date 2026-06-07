<template>
  <section
    class="shelf"
    :class="`shelf--${tone}`"
  >
    <header class="shelf__head">
      <div class="shelf__heading">
        <h2 class="shelf__title">{{ title }}</h2>
        <span
          v-if="count"
          class="shelf__count"
          >{{ count }}</span
        >
      </div>
      <div class="shelf__right">
        <p
          v-if="hint"
          class="shelf__hint"
        >
          {{ hint }}
        </p>
        <div class="shelf__nav">
          <button
            type="button"
            class="shelf__navBtn"
            aria-label="Scroll left"
            @click="scroll(-1)"
          >
            <UIcon name="i-lucide-chevron-left" />
          </button>
          <button
            type="button"
            class="shelf__navBtn"
            aria-label="Scroll right"
            @click="scroll(1)"
          >
            <UIcon name="i-lucide-chevron-right" />
          </button>
        </div>
      </div>
    </header>

    <div
      ref="track"
      class="shelf__track"
    >
      <slot />
    </div>
  </section>
</template>

<script setup lang="ts">
import { useTemplateRef } from 'vue';

defineProps<{
  title: string;
  hint?: string;
  count?: number;
  tone?: 'rediscover';
}>();

const track = useTemplateRef<HTMLDivElement>('track');
function scroll(dir: number) {
  track.value?.scrollBy({ left: dir * Math.round(track.value.clientWidth * 0.8), behavior: 'smooth' });
}
</script>

<style scoped>
.shelf {
  display: grid;
  gap: 0.9rem;
}
.shelf__head {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 16px;
  padding: 0 2rem;
}
.shelf__heading {
  display: inline-flex;
  align-items: baseline;
  gap: 10px;
}
.shelf__title {
  font-size: 1.15rem;
  font-weight: 600;
  letter-spacing: -0.01em;
  color: var(--ui-text-highlighted);
}
.shelf--rediscover .shelf__title::before {
  content: '';
  display: inline-block;
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--ui-warning);
  margin-right: 8px;
  vertical-align: middle;
}
.shelf__count {
  font-size: 0.72rem;
  font-weight: 600;
  color: var(--ui-text-dimmed);
  background: var(--ui-bg-elevated);
  border: 1px solid var(--ui-border);
  padding: 1px 8px;
  border-radius: 999px;
}
.shelf__right {
  display: inline-flex;
  align-items: center;
  gap: 14px;
}
.shelf__hint {
  font-size: 0.78rem;
  color: var(--ui-text-muted);
}
.shelf__nav {
  display: inline-flex;
  gap: 4px;
}
.shelf__navBtn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 999px;
  border: 1px solid var(--ui-border);
  background: var(--ui-bg);
  color: var(--ui-text-muted);
  cursor: pointer;
  transition:
    background 0.12s ease,
    color 0.12s ease;
}
.shelf__navBtn:hover {
  background: var(--ui-bg-elevated);
  color: var(--ui-text);
}

.shelf__track {
  display: flex;
  gap: 14px;
  overflow-x: auto;
  scroll-snap-type: x proximity;
  padding: 4px 2rem 14px;
  scrollbar-width: thin;
}
.shelf__track::-webkit-scrollbar {
  height: 6px;
}
.shelf__track::-webkit-scrollbar-thumb {
  background: var(--ui-border-accented);
  border-radius: 999px;
}
</style>
