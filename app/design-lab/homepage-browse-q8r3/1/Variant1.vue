<template>
  <div class="gz">
    <!-- Masthead -->
    <header class="gz__masthead">
      <div class="gz__mastTop">
        <span class="gz__mastKicker">Est. from your reading</span>
        <span class="gz__mastKicker gz__mastKicker--r">{{ today }}</span>
      </div>
      <h1 class="gz__wordmark">The Enchiridion</h1>
      <div class="gz__mastBottom">
        <span class="gz__rule" />
        <span class="gz__mastSub">Field notes, sources &amp; ideas · {{ records.length }} entries</span>
        <span class="gz__rule" />
      </div>
    </header>

    <div class="gz__body">
      <!-- Lead well -->
      <section class="gz__lead">
        <article
          v-if="lead"
          class="gz__hero"
        >
          <RouterLink
            class="gz__heroImageWrap"
            :to="`/${lead.slug}`"
          >
            <img
              class="gz__heroImage"
              loading="lazy"
              :src="img(lead)"
              :alt="lead.title ?? ''"
            />
          </RouterLink>
          <p class="gz__kicker">{{ kickerFor(lead) }}</p>
          <h2 class="gz__heroTitle">
            <RouterLink :to="`/${lead.slug}`">{{ lead.title }}</RouterLink>
          </h2>
          <p class="gz__deck">{{ plain(lead.summary || lead.content) }}</p>
          <p class="gz__byline">{{ bylineFor(lead) }}</p>
        </article>

        <div class="gz__secondaries">
          <article
            v-for="r in secondaries"
            :key="r.id"
            class="gz__secondary"
          >
            <RouterLink
              v-if="img(r)"
              class="gz__secImageWrap"
              :to="`/${r.slug}`"
            >
              <img
                class="gz__secImage"
                loading="lazy"
                :src="img(r)"
                :alt="r.title ?? ''"
              />
            </RouterLink>
            <p class="gz__kicker">{{ kickerFor(r) }}</p>
            <h3 class="gz__secTitle">
              <RouterLink :to="`/${r.slug}`">{{ r.title }}</RouterLink>
            </h3>
            <p class="gz__secDeck">{{ plain(r.summary || r.content) }}</p>
            <p class="gz__byline">{{ bylineFor(r) }}</p>
          </article>
        </div>
      </section>

      <!-- Latest rail -->
      <aside class="gz__rail">
        <h4 class="gz__railHead">Latest</h4>
        <ol class="gz__briefs">
          <li
            v-for="r in latest"
            :key="r.id"
            class="gz__brief"
          >
            <RouterLink
              class="gz__briefTitle"
              :to="`/${r.slug}`"
            >
              {{ r.title }}
            </RouterLink>
            <p class="gz__briefMeta">
              <UIcon
                class="gz__briefGlyph"
                :name="icon(r.type)"
              />
              <span>{{ capitalize(r.type) }}</span>
              <span class="gz__dot">·</span>
              <span>{{ date(r) }}</span>
              <template v-if="host(r)">
                <span class="gz__dot">·</span>
                <span class="gz__briefHost">{{ host(r) }}</span>
              </template>
            </p>
          </li>
        </ol>
      </aside>
    </div>

    <!-- Archive columns -->
    <section class="gz__archive">
      <div class="gz__sectionHead">
        <span class="gz__sectionRule" />
        <span class="gz__sectionLabel">From the archive</span>
        <span class="gz__sectionRule" />
      </div>
      <div class="gz__columns">
        <article
          v-for="r in archive"
          :key="r.id"
          class="gz__entry"
        >
          <h5 class="gz__entryTitle">
            <RouterLink :to="`/${r.slug}`">{{ r.title }}</RouterLink>
          </h5>
          <p
            v-if="plain(r.summary || r.content)"
            class="gz__entryDeck"
          >
            {{ plain(r.summary || r.content) }}
          </p>
          <p class="gz__entryMeta">{{ capitalize(r.type) }} · {{ date(r) }}</p>
        </article>
      </div>
    </section>

    <!-- Concepts footer -->
    <footer
      v-if="tags.length"
      class="gz__concepts"
    >
      <span class="gz__conceptsLabel">Concepts in rotation</span>
      <RouterLink
        v-for="t in tags"
        :key="t.slug"
        class="gz__concept"
        :to="`/${t.slug}`"
      >
        {{ t.title }}<span class="gz__conceptCount">{{ t.count }}</span>
      </RouterLink>
    </footer>
  </div>
</template>

<script setup lang="ts">
import { getIconForRecordType } from '@app/utils';
import { capitalize, formatDate } from '@shared/lib/formatting';
import { computed } from 'vue';
import {
  bylineParts,
  creatorOf,
  firstImage,
  hostOf,
  plain,
  useLabRecords,
  type LabRecord,
} from '../useLabRecords';

const { records, titled, withImage, topTags, backendBaseUrl } = useLabRecords();

const today = new Date().toLocaleDateString('en-US', {
  weekday: 'long',
  month: 'long',
  day: 'numeric',
});

const lead = computed(() => withImage.value[0] ?? titled.value[0] ?? null);
const secondaries = computed(() =>
  withImage.value.filter((r) => r.id !== lead.value?.id).slice(0, 2),
);

const usedIds = computed(
  () => new Set([lead.value?.id, ...secondaries.value.map((r) => r.id)].filter(Boolean)),
);
const latest = computed(() => titled.value.filter((r) => !usedIds.value.has(r.id)).slice(0, 11));
const archive = computed(() => {
  const skip = new Set([...usedIds.value, ...latest.value.map((r) => r.id)]);
  return titled.value.filter((r) => !skip.has(r.id)).slice(0, 27);
});
const tags = computed(() => topTags.value.slice(0, 14));

function img(r: LabRecord) {
  return `${backendBaseUrl}${firstImage(r)}`;
}
function icon(type: LabRecord['type']) {
  return getIconForRecordType(type);
}
function host(r: LabRecord) {
  return hostOf(r);
}
function date(r: LabRecord) {
  return r.recordCreatedAt ? formatDate(r.recordCreatedAt, { year: false }) : '';
}
function kickerFor(r: LabRecord) {
  const c = creatorOf(r);
  if (c?.title) return c.title;
  if (host(r)) return host(r);
  return capitalize(r.type);
}
function bylineFor(r: LabRecord) {
  return bylineParts(r).join(' · ');
}
</script>

<style scoped>
.gz {
  --serif: var(--font-serif);
  max-width: 1180px;
  margin: 0 auto;
  padding: 2.5rem 2rem 4rem;
  color: var(--ui-text-highlighted);
}

/* Masthead */
.gz__masthead {
  text-align: center;
  margin-bottom: 2rem;
}
.gz__mastTop {
  display: flex;
  justify-content: space-between;
  font-size: 0.65rem;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--ui-text-muted);
  border-bottom: 1px solid var(--ui-text-highlighted);
  padding-bottom: 6px;
}
.gz__mastKicker--r {
  text-align: right;
}
.gz__wordmark {
  font-family: var(--serif);
  font-weight: 600;
  font-size: clamp(2.6rem, 5vw, 4rem);
  line-height: 1;
  letter-spacing: -0.02em;
  margin: 0.5rem 0 0.6rem;
}
.gz__mastBottom {
  display: grid;
  grid-template-columns: 1fr auto 1fr;
  align-items: center;
  gap: 12px;
}
.gz__rule {
  height: 3px;
  border-top: 1px solid var(--ui-text-highlighted);
  border-bottom: 1px solid var(--ui-text-highlighted);
}
.gz__mastSub {
  font-size: 0.7rem;
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: var(--ui-text-muted);
  white-space: nowrap;
}

/* Lead well + rail */
.gz__body {
  display: grid;
  grid-template-columns: minmax(0, 2.3fr) minmax(220px, 1fr);
  gap: 2.5rem;
  border-top: 2px solid var(--ui-text-highlighted);
  padding-top: 1.5rem;
}

.gz__hero {
  border-bottom: 1px solid var(--ui-border);
  padding-bottom: 1.5rem;
  margin-bottom: 1.5rem;
}
.gz__heroImageWrap {
  display: block;
  margin-bottom: 1rem;
}
.gz__heroImage {
  width: 100%;
  height: 340px;
  object-fit: cover;
  object-position: 50% 30%;
  border-radius: var(--radius-md);
  filter: saturate(0.95);
}
.gz__kicker {
  font-size: 0.62rem;
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: var(--ui-primary);
  font-weight: 600;
  margin-bottom: 4px;
}
.gz__heroTitle {
  font-family: var(--serif);
  font-weight: 600;
  font-size: clamp(1.8rem, 3.2vw, 2.7rem);
  line-height: 1.05;
  letter-spacing: -0.02em;
  margin-bottom: 0.6rem;
}
.gz__heroTitle a:hover {
  color: var(--ui-primary);
}
.gz__deck {
  font-family: var(--serif);
  font-size: 1.05rem;
  line-height: 1.5;
  color: var(--ui-text-toned);
  display: -webkit-box;
  -webkit-line-clamp: 3;
  line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
  margin-bottom: 0.6rem;
}
.gz__byline {
  font-size: 0.72rem;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--ui-text-muted);
}

.gz__secondaries {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 2rem;
}
.gz__secImageWrap {
  display: block;
  margin-bottom: 0.7rem;
}
.gz__secImage {
  width: 100%;
  height: 150px;
  object-fit: cover;
  object-position: 50% 30%;
  border-radius: var(--radius-md);
}
.gz__secTitle {
  font-family: var(--serif);
  font-weight: 600;
  font-size: 1.3rem;
  line-height: 1.12;
  letter-spacing: -0.01em;
  margin-bottom: 0.4rem;
}
.gz__secTitle a:hover {
  color: var(--ui-primary);
}
.gz__secDeck {
  font-size: 0.85rem;
  line-height: 1.45;
  color: var(--ui-text-muted);
  display: -webkit-box;
  -webkit-line-clamp: 3;
  line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
  margin-bottom: 0.5rem;
}

/* Rail */
.gz__rail {
  border-left: 1px solid var(--ui-border);
  padding-left: 1.5rem;
}
.gz__railHead {
  font-family: var(--serif);
  font-size: 1.1rem;
  font-weight: 600;
  padding-bottom: 8px;
  margin-bottom: 4px;
  border-bottom: 2px solid var(--ui-text-highlighted);
}
.gz__briefs {
  display: grid;
}
.gz__brief {
  padding: 0.75rem 0;
  border-bottom: 1px solid var(--ui-border);
}
.gz__briefTitle {
  font-family: var(--serif);
  font-size: 1rem;
  font-weight: 500;
  line-height: 1.25;
  display: block;
  margin-bottom: 4px;
}
.gz__briefTitle:hover {
  color: var(--ui-primary);
}
.gz__briefMeta {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 0.68rem;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--ui-text-muted);
}
.gz__briefGlyph {
  width: 12px;
  height: 12px;
}
.gz__dot {
  opacity: 0.5;
}
.gz__briefHost {
  text-transform: none;
  letter-spacing: 0;
  color: var(--ui-text-dimmed);
}

/* Archive */
.gz__archive {
  margin-top: 2.5rem;
}
.gz__sectionHead {
  display: grid;
  grid-template-columns: 1fr auto 1fr;
  align-items: center;
  gap: 14px;
  margin-bottom: 1.5rem;
}
.gz__sectionRule {
  height: 1px;
  background: var(--ui-text-highlighted);
}
.gz__sectionLabel {
  font-size: 0.7rem;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--ui-text-muted);
  font-weight: 600;
}
.gz__columns {
  columns: 3 200px;
  column-gap: 2rem;
}
.gz__entry {
  break-inside: avoid;
  padding-bottom: 1.1rem;
  margin-bottom: 1.1rem;
  border-bottom: 1px solid var(--ui-border);
}
.gz__entryTitle {
  font-family: var(--serif);
  font-size: 1.05rem;
  font-weight: 600;
  line-height: 1.2;
  margin-bottom: 0.3rem;
}
.gz__entryTitle a:hover {
  color: var(--ui-primary);
}
.gz__entryDeck {
  font-size: 0.8rem;
  line-height: 1.4;
  color: var(--ui-text-muted);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  margin-bottom: 0.35rem;
}
.gz__entryMeta {
  font-size: 0.65rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--ui-text-dimmed);
}

/* Concepts footer */
.gz__concepts {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  margin-top: 2.5rem;
  padding-top: 1.5rem;
  border-top: 2px solid var(--ui-text-highlighted);
}
.gz__conceptsLabel {
  font-size: 0.68rem;
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: var(--ui-text-muted);
  font-weight: 600;
  margin-right: 6px;
}
.gz__concept {
  display: inline-flex;
  align-items: baseline;
  gap: 5px;
  padding: 4px 10px;
  border: 1px solid var(--ui-border);
  border-radius: 999px;
  font-family: var(--serif);
  font-size: 0.85rem;
  background: var(--ui-bg);
  transition: border-color 0.12s ease;
}
.gz__concept:hover {
  border-color: var(--ui-primary);
  color: var(--ui-primary);
}
.gz__conceptCount {
  font-family: var(--font-sans);
  font-size: 0.6rem;
  color: var(--ui-text-dimmed);
}

@media (max-width: 900px) {
  .gz__body {
    grid-template-columns: 1fr;
  }
  .gz__rail {
    border-left: 0;
    padding-left: 0;
  }
}
</style>
