<template>
  <div class="Lab">
    <header class="Lab__bar">
      <div class="Lab__barLeft">
        <span class="Lab__brief">Design lab · {{ brief }}</span>
      </div>

      <div class="Lab__barCenter">
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
        <span class="Lab__roundLabel">
          Round {{ currentRound?.n ?? '?' }}
          <span class="Lab__roundMode">{{ currentRound?.mode }}</span>
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

      <div class="Lab__barRight">
        <span
          v-if="working"
          class="Lab__working"
        >
          <span class="Lab__pulse" />
          working…
        </span>
        <span class="Lab__lineage">
          <span
            v-for="step in lineage"
            :key="step.n"
            class="Lab__lineageStep"
          >
            <RouterLink :to="`/design-lab/${slug}/${step.n}`">{{ step.n }}</RouterLink>
            <span
              v-if="step.note"
              class="Lab__lineageNote"
              :title="step.note"
            >
              ✱
            </span>
          </span>
        </span>
      </div>
    </header>

    <div
      v-if="currentRound && currentRound.variants.length > 1"
      class="Lab__tabs"
    >
      <button
        v-for="(variant, index) in currentRound.variants"
        :key="index"
        type="button"
        class="Lab__tab"
        :class="{ 'Lab__tab--active': activeTab === index }"
        @click="activeTab = index"
      >
        <span class="Lab__tabNumber">{{ index + 1 }}</span>
        <span class="Lab__tabLabel">{{ variant.label }}</span>
      </button>
    </div>

    <div
      v-if="currentRound && activeVariant"
      class="Lab__stage"
    >
      <div class="Lab__variantHeader">
        <div class="Lab__variantHeading">
          <h2 class="Lab__variantTitle">{{ activeTab + 1 }}. {{ activeVariant.label }}</h2>
          <p
            v-if="activeVariant.blurb"
            class="Lab__variantBlurb"
          >
            {{ activeVariant.blurb }}
          </p>
        </div>

        <div class="Lab__variantActions">
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
        class="Lab__noteBar"
      >
        <UInput
          v-model="note"
          placeholder="What to change / explore further"
          class="Lab__noteInput"
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

      <div class="Lab__stageScroll">
        <component :is="activeComponent" />
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, defineAsyncComponent, ref, watch } from 'vue';
import { RouterLink, useRoute, useRouter } from 'vue-router';
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

const variantModules = import.meta.glob('./*/Variant*.vue');
const activeComponent = computed(() => {
  if (!activeVariant.value || !currentRound.value) return null;
  const loader = variantModules[`./${activeVariant.value.file}`];
  if (!loader) return null;
  return defineAsyncComponent(loader as () => Promise<Record<string, unknown>>);
});

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

const heartbeat = window.setInterval(() => {
  working.value = !!localStorage.getItem(`designLab:${slug}:pick`);
}, 1500);
// eslint-disable-next-line @typescript-eslint/no-unused-expressions
() => clearInterval(heartbeat);

if (!route.params.n) {
  router.replace(`/design-lab/${slug}/${currentRoundNumber.value}`);
}
</script>

<style scoped>
.Lab {
  display: grid;
  grid-template-rows: auto auto auto 1fr;
  height: 100%;
  min-height: 0;
  background: var(--page-bg);
  color: var(--ui-text);
}

.Lab__bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 8px 16px;
  border-bottom: 1px solid var(--ui-border);
  background: var(--ui-bg-elevated);
  font-size: 0.75rem;
}

.Lab__barCenter {
  display: flex;
  align-items: center;
  gap: 8px;
}

.Lab__roundLabel {
  font-weight: 600;
  display: inline-flex;
  align-items: baseline;
  gap: 6px;
}

.Lab__roundMode {
  font-weight: 400;
  font-size: 0.65rem;
  text-transform: uppercase;
  color: var(--ui-text-dimmed);
  letter-spacing: 0.04em;
}

.Lab__brief {
  color: var(--ui-text-muted);
}

.Lab__working {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  color: var(--ui-primary);
}

.Lab__pulse {
  display: inline-block;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--ui-primary);
  animation: lab-pulse 1.2s ease-in-out infinite;
}

@keyframes lab-pulse {
  0%,
  100% {
    opacity: 0.35;
    transform: scale(0.85);
  }
  50% {
    opacity: 1;
    transform: scale(1.1);
  }
}

.Lab__lineage {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  color: var(--ui-text-dimmed);
}

.Lab__lineageStep {
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

.Lab__lineageNote {
  font-size: 0.6rem;
  color: var(--ui-primary);
  cursor: help;
}

.Lab__tabs {
  display: flex;
  gap: 0;
  border-bottom: 1px solid var(--ui-border);
  background: var(--ui-bg);
  overflow-x: auto;
}

.Lab__tab {
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

.Lab__tab:hover {
  background: var(--ui-bg-elevated);
}

.Lab__tab--active {
  color: var(--ui-text);
  background: var(--ui-bg-elevated);
  box-shadow: inset 0 -2px 0 var(--ui-primary);
}

.Lab__tabNumber {
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

.Lab__tabLabel {
  white-space: nowrap;
}

.Lab__stage {
  display: grid;
  grid-template-rows: auto auto 1fr;
  overflow: hidden;
  min-height: 0;
}

.Lab__variantHeader {
  display: flex;
  justify-content: space-between;
  align-items: start;
  gap: 16px;
  padding: 12px 20px;
  border-bottom: 1px solid var(--ui-border);
  background: var(--ui-bg-elevated);
}

.Lab__variantHeading {
  display: grid;
  gap: 2px;
  max-width: 70%;
}

.Lab__variantTitle {
  font-size: 0.95rem;
  font-weight: 600;
}

.Lab__variantBlurb {
  font-size: 0.8rem;
  color: var(--ui-text-muted);
}

.Lab__variantActions {
  display: inline-flex;
  gap: 6px;
  align-items: center;
}

.Lab__noteBar {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 20px;
  background: var(--ui-bg-elevated);
  border-bottom: 1px solid var(--ui-border);
}

.Lab__noteInput {
  flex: 1;
}

/* Full-bleed canvas — the variant IS the whole homepage. */
.Lab__stageScroll {
  overflow-y: auto;
  min-height: 0;
  background: var(--page-bg);
}
</style>
