<template>
  <div
    ref="root"
    class="IndexSearchInput"
    :class="{ 'IndexSearchInput--collapsed': !showInput }"
  >
    <button
      v-if="!showInput"
      type="button"
      class="IndexSearchInput__logo"
      aria-label="Enchiridion — search records"
      @click="open"
    >
      Enchiridion
    </button>
    <div
      v-else
      class="IndexSearchInput__field"
    >
      <UIcon
        name="i-lucide-search"
        class="IndexSearchInput__icon"
      />
      <UInput
        v-model="model"
        placeholder="Search records…"
        size="xs"
        variant="ghost"
        class="IndexSearchInput__input"
        @blur="onBlur"
        @keydown.esc="clear"
      />
      <UButton
        v-if="model"
        icon="i-lucide-x"
        size="xs"
        color="neutral"
        variant="ghost"
        class="IndexSearchInput__clear"
        aria-label="Clear search"
        @click="clear"
      />
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, nextTick, ref, useTemplateRef } from 'vue';

// The serif logo doubles as the search entry point: click it to reveal the
// input. Keystrokes flow straight through v-model — the parent owns debouncing
// and the URL mirror (`?q=`), since both are routing concerns.
const model = defineModel<string>({ default: '' });

// `isOpen` tracks the logo→input toggle; a non-empty query forces it open so a
// deep-linked `?q=` lands on the expanded input, not the collapsed logo. The
// gate is trimmed so a whitespace-only `?q=` (which runs no search) stays
// collapsed as the logo.
const hasQuery = computed(() => model.value.trim().length > 0);
const isOpen = ref(hasQuery.value);
const showInput = computed(() => isOpen.value || hasQuery.value);

const root = useTemplateRef<HTMLElement>('root');

function open() {
  isOpen.value = true;
  nextTick(() => root.value?.querySelector('input')?.focus());
}

function onBlur() {
  // Collapse back to the logo only when there's nothing to keep showing.
  if (!model.value) isOpen.value = false;
}

function clear() {
  model.value = '';
  isOpen.value = false;
  // Collapsing unmounts the focused input; hand focus to the logo button so
  // keyboard users keep their place in the toolbar.
  nextTick(() => root.value?.querySelector('button')?.focus());
}
</script>

<style scoped>
.IndexSearchInput {
  display: inline-flex;
  align-items: center;
  min-width: 0;
}

/* Extra breathing room between the serif logo and the view toggles next to it.
 * Only while collapsed — once the search input is open it should sit at the
 * toolbar's normal gap, so the field doesn't get pushed off-center. */
.IndexSearchInput--collapsed {
  margin-right: 8px;
}

.IndexSearchInput__logo {
  font-family: var(--font-serif, 'Georgia', serif);
  font-size: 1.05rem;
  font-weight: 500;
  line-height: 1.2;
  letter-spacing: 0.01em;
  color: var(--ui-text);
  background: transparent;
  border: 0;
  padding: 0;
  margin: 0;
  white-space: nowrap;
  cursor: text;
  transition: color 0.15s ease;
}

.IndexSearchInput__logo:hover {
  color: var(--ui-text-muted);
}

.IndexSearchInput__field {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  width: 200px;
  max-width: 32vw;
}

.IndexSearchInput__icon {
  flex: none;
  width: 16px;
  height: 16px;
  color: var(--ui-text-dimmed);
}

:deep(.IndexSearchInput__input) {
  flex: 1;
  min-width: 0;

  & input {
    /* Match the collapsed logo / toolbar-control height (24px) so swapping the
     * logo for the input doesn't nudge the toolbar taller. */
    height: 24px;
    font-family: var(--font-serif, 'Georgia', serif);
    font-size: 0.95rem;
    padding-block: 0;
    padding-inline: 0;
    background-color: transparent;
  }
}

:deep(.IndexSearchInput__clear svg) {
  color: var(--ui-text-muted);
}

/* Phones: the search field fills the toolbar row when open (32vw collapses it to
 * an unusable ~125px). */
@media (max-width: 640px) {
  .IndexSearchInput__field {
    width: 100%;
    max-width: 100%;
  }
}
</style>
