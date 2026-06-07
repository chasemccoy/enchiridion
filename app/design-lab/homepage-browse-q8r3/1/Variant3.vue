<template>
  <div class="hb">
    <!-- Themed index rail -->
    <aside class="hb__rail">
      <div class="hb__railInner">
        <h2 class="hb__railTitle">Index</h2>
        <p class="hb__railSub">Themes by frequency</p>
        <ul class="hb__themes">
          <li
            v-for="t in themes"
            :key="t.slug"
          >
            <RouterLink
              class="hb__theme"
              :to="`/${t.slug}`"
            >
              <span class="hb__themeName">{{ t.title }}</span>
              <span class="hb__themeBarWrap">
                <span
                  class="hb__themeBar"
                  :style="{ width: `${(t.count / maxTheme) * 100}%` }"
                />
              </span>
              <span class="hb__themeCount">{{ t.count }}</span>
            </RouterLink>
          </li>
        </ul>

        <h3 class="hb__railSection">Browse by kind</h3>
        <nav class="hb__kinds">
          <a
            v-for="k in kinds"
            :key="k.type"
            class="hb__kind"
            :href="`#hb-${k.type}`"
          >
            <UIcon
              class="hb__kindGlyph"
              :name="k.icon"
            />
            <span>{{ k.label }}</span>
            <span class="hb__kindCount">{{ k.count }}</span>
          </a>
        </nav>
      </div>
    </aside>

    <!-- Directory -->
    <main class="hb__main">
      <header class="hb__masthead">
        <p class="hb__eyebrow">A handbook of {{ records.length }} entries</p>
        <h1 class="hb__title">The Enchiridion</h1>
        <p class="hb__lede">
          Everything you’ve gathered, indexed by theme and kind — a reference you can read end to
          end or jump into anywhere.
        </p>
      </header>

      <!-- Hubs -->
      <section class="hb__hubsSection">
        <div class="hb__sectionHead">
          <span class="hb__sectionLabel">Most connected</span>
          <span class="hb__sectionRule" />
        </div>
        <div class="hb__hubs">
          <RouterLink
            v-for="r in hubs"
            :key="r.id"
            class="hb__hub"
            :to="`/${r.slug}`"
          >
            <span class="hb__hubLinks">
              <UIcon
                name="i-lucide-share-2"
                class="hb__hubGlyph"
              />
              {{ connections(r) }}
            </span>
            <span class="hb__hubTitle">{{ r.title }}</span>
            <span class="hb__hubType">{{ capitalize(r.type) }}</span>
          </RouterLink>
        </div>
      </section>

      <!-- By kind -->
      <section
        v-for="k in kinds"
        :key="k.type"
        :id="`hb-${k.type}`"
        class="hb__kindSection"
      >
        <div class="hb__sectionHead">
          <UIcon
            class="hb__sectionGlyph"
            :name="k.icon"
          />
          <span class="hb__sectionLabel">{{ k.label }}</span>
          <span class="hb__sectionCount">{{ k.count }}</span>
          <span class="hb__sectionRule" />
        </div>
        <ul class="hb__entries">
          <li
            v-for="r in k.records"
            :key="r.id"
            class="hb__entry"
          >
            <RouterLink
              class="hb__entryLink"
              :to="`/${r.slug}`"
            >
              <span class="hb__entryTitle">{{ r.title }}</span>
              <span
                v-if="entryMeta(r)"
                class="hb__entryMeta"
                >{{ entryMeta(r) }}</span
              >
            </RouterLink>
          </li>
        </ul>
      </section>
    </main>
  </div>
</template>

<script setup lang="ts">
import { getIconForRecordType } from '@app/utils';
import { capitalize } from '@shared/lib/formatting';
import { computed } from 'vue';
import { hostOf, useLabRecords, type LabRecord } from '../useLabRecords';

const { records, titled, byType, topTags } = useLabRecords();

const themes = computed(() => topTags.value.slice(0, 22));
const maxTheme = computed(() => themes.value[0]?.count ?? 1);

function connections(r: LabRecord) {
  return (r.outgoingLinks?.length ?? 0) + (r.incomingLinks?.length ?? 0);
}
const hubs = computed(() =>
  [...titled.value].sort((a, b) => connections(b) - connections(a)).slice(0, 6),
);

const alpha = (list: LabRecord[]) =>
  [...list].sort((a, b) => (a.title ?? '').localeCompare(b.title ?? ''));

const kinds = computed(() => [
  {
    type: 'artifact' as const,
    label: 'Artifacts',
    icon: getIconForRecordType('artifact'),
    count: byType.value.artifact.length,
    records: alpha(byType.value.artifact),
  },
  {
    type: 'concept' as const,
    label: 'Concepts',
    icon: getIconForRecordType('concept'),
    count: byType.value.concept.length,
    records: alpha(byType.value.concept),
  },
  {
    type: 'entity' as const,
    label: 'Entities',
    icon: getIconForRecordType('entity'),
    count: byType.value.entity.length,
    records: alpha(byType.value.entity),
  },
]);

function entryMeta(r: LabRecord) {
  return hostOf(r) ?? '';
}
</script>

<style scoped>
.hb {
  display: grid;
  grid-template-columns: 248px minmax(0, 1fr);
  gap: 0;
  align-items: start;
  max-width: 1240px;
  margin: 0 auto;
}

/* Rail */
.hb__rail {
  position: sticky;
  top: 0;
  align-self: start;
  border-right: 1px solid var(--ui-border);
}
.hb__railInner {
  padding: 2.25rem 1.5rem 2rem;
  max-height: 100%;
}
.hb__railTitle {
  font-family: var(--font-serif);
  font-size: 1.35rem;
  font-weight: 600;
  color: var(--ui-text-highlighted);
}
.hb__railSub {
  font-size: 0.66rem;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  color: var(--ui-text-dimmed);
  margin-bottom: 1rem;
}
.hb__themes {
  display: grid;
  gap: 1px;
}
.hb__theme {
  display: grid;
  grid-template-columns: 1fr 38px auto;
  align-items: center;
  gap: 8px;
  padding: 4px 0;
  font-size: 0.82rem;
  color: var(--ui-text-toned);
}
.hb__theme:hover .hb__themeName {
  color: var(--ui-primary);
}
.hb__themeName {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.hb__themeBarWrap {
  height: 4px;
  background: var(--ui-bg-elevated);
  border-radius: 999px;
  overflow: hidden;
}
.hb__themeBar {
  display: block;
  height: 100%;
  background: var(--ui-primary);
  opacity: 0.8;
  border-radius: 999px;
}
.hb__themeCount {
  font-size: 0.68rem;
  color: var(--ui-text-dimmed);
  font-variant-numeric: tabular-nums;
}
.hb__railSection {
  margin-top: 1.5rem;
  margin-bottom: 0.6rem;
  font-size: 0.66rem;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  color: var(--ui-text-dimmed);
}
.hb__kinds {
  display: grid;
  gap: 2px;
}
.hb__kind {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 6px 8px;
  border-radius: var(--radius-md);
  font-size: 0.85rem;
  color: var(--ui-text-toned);
}
.hb__kind:hover {
  background: var(--ui-bg-elevated);
}
.hb__kindGlyph {
  width: 15px;
  height: 15px;
  color: var(--ui-text-muted);
}
.hb__kindCount {
  margin-left: auto;
  font-size: 0.7rem;
  color: var(--ui-text-dimmed);
  font-variant-numeric: tabular-nums;
}

/* Main */
.hb__main {
  padding: 2.25rem 2.5rem 4rem;
  min-width: 0;
}
.hb__masthead {
  margin-bottom: 2.25rem;
  max-width: 640px;
}
.hb__eyebrow {
  font-size: 0.66rem;
  text-transform: uppercase;
  letter-spacing: 0.16em;
  color: var(--ui-primary);
  font-weight: 600;
}
.hb__title {
  font-family: var(--font-serif);
  font-size: clamp(2.2rem, 4vw, 3rem);
  font-weight: 600;
  letter-spacing: -0.02em;
  line-height: 1;
  margin: 6px 0 10px;
  color: var(--ui-text-highlighted);
}
.hb__lede {
  font-family: var(--font-serif);
  font-size: 1.05rem;
  line-height: 1.5;
  color: var(--ui-text-muted);
}

.hb__sectionHead {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 1.1rem;
}
.hb__sectionGlyph {
  width: 16px;
  height: 16px;
  color: var(--ui-text-muted);
}
.hb__sectionLabel {
  font-size: 0.72rem;
  text-transform: uppercase;
  letter-spacing: 0.14em;
  font-weight: 600;
  color: var(--ui-text-toned);
}
.hb__sectionCount {
  font-size: 0.68rem;
  font-weight: 600;
  color: var(--ui-text-dimmed);
  background: var(--ui-bg-elevated);
  border: 1px solid var(--ui-border);
  padding: 0 7px;
  border-radius: 999px;
  font-variant-numeric: tabular-nums;
}
.hb__sectionRule {
  flex: 1;
  height: 1px;
  background: var(--ui-border);
}

/* Hubs */
.hb__hubsSection {
  margin-bottom: 2.5rem;
}
.hb__hubs {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
  gap: 10px;
}
.hb__hub {
  display: grid;
  gap: 6px;
  padding: 14px;
  border: 1px solid var(--ui-border);
  border-radius: var(--radius-lg);
  background: var(--ui-bg);
  transition:
    border-color 0.12s ease,
    box-shadow 0.12s ease;
}
.hb__hub:hover {
  border-color: var(--ui-border-accented);
  box-shadow: 0 8px 22px -16px rgba(11, 11, 11, 0.35);
}
.hb__hubLinks {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 0.7rem;
  font-weight: 600;
  color: var(--ui-primary);
  font-variant-numeric: tabular-nums;
}
.hb__hubGlyph {
  width: 12px;
  height: 12px;
}
.hb__hubTitle {
  font-size: 0.95rem;
  font-weight: 600;
  line-height: 1.2;
  color: var(--ui-text-highlighted);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.hb__hubType {
  font-size: 0.64rem;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--ui-text-dimmed);
}

/* Entries */
.hb__kindSection {
  margin-bottom: 2.5rem;
  scroll-margin-top: 1rem;
}
.hb__entries {
  columns: 3 220px;
  column-gap: 2rem;
}
.hb__entry {
  break-inside: avoid;
  content-visibility: auto;
  contain-intrinsic-size: 0 30px;
}
.hb__entryLink {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 10px;
  padding: 4px 0;
  border-bottom: 1px solid var(--ui-border-muted);
}
.hb__entryLink:hover .hb__entryTitle {
  color: var(--ui-primary);
}
.hb__entryTitle {
  font-size: 0.85rem;
  line-height: 1.3;
  color: var(--ui-text-toned);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.hb__entryMeta {
  flex: 0 0 auto;
  font-size: 0.65rem;
  color: var(--ui-text-dimmed);
  max-width: 38%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

@media (max-width: 880px) {
  .hb {
    grid-template-columns: 1fr;
  }
  .hb__rail {
    position: static;
    border-right: 0;
    border-bottom: 1px solid var(--ui-border);
  }
}
</style>
