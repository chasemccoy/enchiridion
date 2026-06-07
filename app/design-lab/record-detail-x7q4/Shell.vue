<template>
  <div class="DesignLab">
    <header class="DesignLab__bar">
      <div class="DesignLab__barLeft">
        <span class="DesignLab__brief">Design lab · {{ brief }}</span>
      </div>

      <div class="DesignLab__barCenter">
        <UButton
          v-if="prevRound"
          size="xs"
          color="neutral"
          variant="ghost"
          icon="i-lucide-chevron-left"
          :to="`/design-lab/${slug}/${prevRound.n}`"
        >
          Round {{ prevRound.n }}
        </UButton>
        <span class="DesignLab__roundLabel">
          Round {{ currentRound?.n ?? '?' }}
          <span class="DesignLab__roundMode">{{ currentRound?.mode }}</span>
        </span>
        <UButton
          v-if="nextRound"
          size="xs"
          color="neutral"
          variant="ghost"
          trailing-icon="i-lucide-chevron-right"
          :to="`/design-lab/${slug}/${nextRound.n}`"
        >
          Round {{ nextRound.n }}
        </UButton>
      </div>

      <div class="DesignLab__barRight">
        <span
          v-if="working"
          class="DesignLab__working"
        >
          <span class="DesignLab__pulse" />
          working…
        </span>
        <span class="DesignLab__lineage">
          <span
            v-for="step in lineage"
            :key="step.n"
            class="DesignLab__lineageStep"
          >
            <RouterLink :to="`/design-lab/${slug}/${step.n}`">{{ step.n }}</RouterLink>
            <span
              v-if="step.note"
              class="DesignLab__lineageNote"
              :title="step.note"
            >
              ✱
            </span>
          </span>
        </span>
      </div>
    </header>

    <div
      v-if="currentRound?.mode === 'tabs' && currentRound.variants.length > 1"
      class="DesignLab__tabs"
    >
      <button
        v-for="(variant, index) in currentRound.variants"
        :key="index"
        type="button"
        class="DesignLab__tab"
        :class="{ 'DesignLab__tab--active': activeTab === index }"
        @click="activeTab = index"
      >
        <span class="DesignLab__tabNumber">{{ index + 1 }}</span>
        <span class="DesignLab__tabLabel">{{ variant.label }}</span>
      </button>
    </div>

    <div
      v-if="currentRound && activeVariant"
      class="DesignLab__stage"
    >
      <div class="DesignLab__variantHeader">
        <div class="DesignLab__variantHeading">
          <h2 class="DesignLab__variantTitle">
            {{ activeTab + 1 }}. {{ activeVariant.label }}
          </h2>
          <p
            v-if="activeVariant.blurb"
            class="DesignLab__variantBlurb"
          >
            {{ activeVariant.blurb }}
          </p>
        </div>

        <div class="DesignLab__variantActions">
          <UButton
            size="xs"
            color="primary"
            variant="solid"
            label="Choose"
            @click="setPick('choose')"
          />
          <UButton
            size="xs"
            color="neutral"
            variant="subtle"
            label="Variations"
            @click="openNote('variations')"
          />
          <UButton
            size="xs"
            color="neutral"
            variant="outline"
            label="Tune"
            @click="openNote('tune')"
          />
        </div>
      </div>

      <div
        v-if="noteOpen"
        class="DesignLab__noteBar"
      >
        <UInput
          v-model="note"
          placeholder="What to change / explore further"
          class="DesignLab__noteInput"
          autofocus
          @keydown.enter="setPick(noteOpen)"
        />
        <UButton
          size="sm"
          color="primary"
          :label="`Run ${noteOpen}`"
          @click="setPick(noteOpen)"
        />
        <UButton
          size="sm"
          color="neutral"
          variant="ghost"
          label="Cancel"
          @click="noteOpen = null"
        />
      </div>

      <div class="DesignLab__variantFrame">
        <!-- Mocks the SplitViewLayout: 0.35fr list rail on the left so the
             variants render against their real column width. -->
        <aside class="DesignLab__fakeSidebar">
          <div class="DesignLab__fakeSidebarHead">List rail (mocked)</div>
          <div
            v-for="i in 8"
            :key="i"
            class="DesignLab__fakeSidebarItem"
            :class="{ 'DesignLab__fakeSidebarItem--active': i === 3 }"
          >
            <div class="DesignLab__fakeSidebarTitle" />
            <div class="DesignLab__fakeSidebarLine" />
            <div class="DesignLab__fakeSidebarLine DesignLab__fakeSidebarLine--short" />
          </div>
        </aside>
        <div class="DesignLab__variantScroll">
          <component :is="activeComponent" />
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, defineAsyncComponent, ref, watch } from 'vue';
import { useRoute, useRouter, RouterLink } from 'vue-router';
import { brief, rounds, slug } from './manifest';

const route = useRoute();
const router = useRouter();

const currentRoundNumber = computed(() => {
  const fromRoute = Number(route.params.n);
  if (!Number.isNaN(fromRoute) && fromRoute > 0) return fromRoute;
  return rounds[rounds.length - 1]?.n ?? 1;
});
const currentRound = computed(
  () => rounds.find((r) => r.n === currentRoundNumber.value) ?? rounds[rounds.length - 1],
);
const prevRound = computed(() => {
  const sorted = [...rounds].sort((a, b) => a.n - b.n);
  const idx = sorted.findIndex((r) => r.n === currentRound.value?.n);
  return idx > 0 ? sorted[idx - 1] : null;
});
const nextRound = computed(() => {
  const sorted = [...rounds].sort((a, b) => a.n - b.n);
  const idx = sorted.findIndex((r) => r.n === currentRound.value?.n);
  return idx >= 0 && idx < sorted.length - 1 ? sorted[idx + 1] : null;
});

const lineage = computed(() => {
  const trail: { n: number; note?: string }[] = [];
  let cursor = currentRound.value;
  while (cursor) {
    trail.unshift({ n: cursor.n, note: cursor.seededFrom?.note });
    if (!cursor.seededFrom) break;
    const seed = cursor.seededFrom;
    cursor = rounds.find((r) => r.n === seed.round) ?? undefined;
  }
  return trail;
});

const activeTab = ref(0);
watch(currentRoundNumber, () => {
  activeTab.value = 0;
});

const activeVariant = computed(() => currentRound.value?.variants[activeTab.value] ?? null);

// Async-import the variant file based on its path; Vite glob lets us
// resolve dynamic file names at build time.
const variantModules = import.meta.glob('./*/Variant*.vue');
const activeComponent = computed(() => {
  if (!activeVariant.value || !currentRound.value) return null;
  const key = `./${activeVariant.value.file}`;
  const loader = variantModules[key];
  if (!loader) return null;
  return defineAsyncComponent(loader as () => Promise<Record<string, unknown>>);
});

// Pick controls
const noteOpen = ref<'variations' | 'tune' | null>(null);
const note = ref('');
const working = ref(false);

function openNote(kind: 'variations' | 'tune') {
  noteOpen.value = kind;
  note.value = '';
}

function setPick(action: 'choose' | 'variations' | 'tune') {
  if (!currentRound.value) return;
  const payload = {
    round: currentRound.value.n,
    choice: activeTab.value,
    action,
    note: note.value || undefined,
  };
  localStorage.setItem(`designLab:${slug}:pick`, JSON.stringify(payload));
  working.value = true;
  noteOpen.value = null;
  note.value = '';
}

// Heartbeat: shows pulse while a pick is pending.
const heartbeat = window.setInterval(() => {
  const raw = localStorage.getItem(`designLab:${slug}:pick`);
  working.value = !!raw;
}, 1500);
// eslint-disable-next-line @typescript-eslint/no-unused-expressions
() => clearInterval(heartbeat);

// If we land on bare /design-lab/:slug (no round in route), redirect to latest.
if (!route.params.n) {
  router.replace(`/design-lab/${slug}/${currentRoundNumber.value}`);
}
</script>

<style scoped>
.DesignLab {
  display: grid;
  grid-template-rows: auto auto 1fr;
  min-height: 100vh;
  background: var(--ui-bg);
  color: var(--ui-text);
}

.DesignLab__bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 8px 16px;
  border-bottom: 1px solid var(--ui-border);
  background: var(--ui-bg-elevated);
  font-size: 0.75rem;
}

.DesignLab__barCenter {
  display: flex;
  align-items: center;
  gap: 8px;
}

.DesignLab__roundLabel {
  font-weight: 600;
  display: inline-flex;
  align-items: baseline;
  gap: 6px;
}

.DesignLab__roundMode {
  font-weight: 400;
  font-size: 0.65rem;
  text-transform: uppercase;
  color: var(--ui-text-dimmed);
  letter-spacing: 0.04em;
}

.DesignLab__brief {
  color: var(--ui-text-muted);
}

.DesignLab__working {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  color: var(--ui-primary);
}

.DesignLab__pulse {
  display: inline-block;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--ui-primary);
  animation: lab-pulse 1.2s ease-in-out infinite;
}

@keyframes lab-pulse {
  0%, 100% { opacity: 0.35; transform: scale(0.85); }
  50% { opacity: 1; transform: scale(1.1); }
}

.DesignLab__lineage {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  color: var(--ui-text-dimmed);
}

.DesignLab__lineageStep {
  display: inline-flex;
  align-items: center;
  gap: 2px;

  & + & {
    margin-left: 6px;
  }

  & + &::before {
    content: '→';
    margin-right: 6px;
    color: var(--ui-text-dimmed);
  }
}

.DesignLab__lineageNote {
  font-size: 0.6rem;
  color: var(--ui-primary);
  cursor: help;
}

.DesignLab__tabs {
  display: flex;
  gap: 0;
  border-bottom: 1px solid var(--ui-border);
  background: var(--ui-bg);
  overflow-x: auto;
}

.DesignLab__tab {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 14px;
  border: 0;
  background: transparent;
  cursor: pointer;
  color: var(--ui-text-muted);
  border-right: 1px solid var(--ui-border);
  font-size: 0.8rem;
  text-align: left;
  transition: background 0.12s ease;
}

.DesignLab__tab:hover {
  background: var(--ui-bg-elevated);
}

.DesignLab__tab--active {
  color: var(--ui-text);
  background: var(--ui-bg-elevated);
  box-shadow: inset 0 -2px 0 var(--ui-primary);
}

.DesignLab__tabNumber {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 18px;
  height: 18px;
  border-radius: 999px;
  background: var(--ui-bg-accented);
  font-size: 0.7rem;
  font-weight: 600;
}

.DesignLab__tabLabel {
  white-space: nowrap;
}

.DesignLab__stage {
  display: grid;
  grid-template-rows: auto auto 1fr;
  overflow: hidden;
}

.DesignLab__variantHeader {
  display: flex;
  justify-content: space-between;
  align-items: start;
  gap: 16px;
  padding: 12px 20px;
  border-bottom: 1px solid var(--ui-border);
  background: var(--ui-bg-elevated);
}

.DesignLab__variantHeading {
  display: grid;
  gap: 2px;
  max-width: 60%;
}

.DesignLab__variantTitle {
  font-size: 0.95rem;
  font-weight: 600;
}

.DesignLab__variantBlurb {
  font-size: 0.8rem;
  color: var(--ui-text-muted);
}

.DesignLab__variantActions {
  display: inline-flex;
  gap: 6px;
  align-items: center;
}

.DesignLab__noteBar {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 20px;
  background: var(--ui-bg-elevated);
  border-bottom: 1px solid var(--ui-border);
}

.DesignLab__noteInput {
  flex: 1;
}

.DesignLab__variantFrame {
  display: grid;
  grid-template-columns: minmax(400px, 0.35fr) 1fr;
  overflow: hidden;
  min-height: 0;
}

.DesignLab__variantScroll {
  overflow-y: auto;
  padding: 2rem 2rem 4rem 1rem;
}

.DesignLab__fakeSidebar {
  border-right: 1px solid var(--ui-border);
  background: var(--ui-bg-elevated);
  padding: 1.5rem 1.2rem;
  overflow-y: auto;
  display: grid;
  grid-auto-rows: max-content;
  gap: 8px;
  align-content: start;
}

.DesignLab__fakeSidebarHead {
  font-size: 0.65rem;
  color: var(--ui-text-dimmed);
  letter-spacing: 0.05em;
  margin-bottom: 4px;
}

.DesignLab__fakeSidebarItem {
  display: grid;
  gap: 6px;
  padding: 10px 12px;
  border-radius: var(--radius-lg);
  background: var(--ui-bg);
  border: 1px solid var(--ui-border);
}

.DesignLab__fakeSidebarItem--active {
  background: var(--ui-bg-accented);
  border-color: var(--ui-border-accented);
}

.DesignLab__fakeSidebarTitle {
  height: 10px;
  background: var(--ui-border);
  border-radius: 3px;
  width: 70%;
}

.DesignLab__fakeSidebarLine {
  height: 6px;
  background: var(--ui-border);
  border-radius: 3px;
  width: 100%;
  opacity: 0.7;
}

.DesignLab__fakeSidebarLine--short {
  width: 60%;
}
</style>
