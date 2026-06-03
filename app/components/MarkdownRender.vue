<template>
  <div
    class="MarkdownRender"
    v-html="html"
  />
</template>

<script setup lang="ts">
import DOMPurify from 'dompurify';
import MarkdownIt from 'markdown-it';
import { computed } from 'vue';

const { source } = defineProps<{
  source?: string | null;
}>();

const md = new MarkdownIt({
  html: false,
  linkify: true,
  breaks: true,
  typographer: true,
});

const html = computed(() => DOMPurify.sanitize(md.render(source ?? '')));
</script>

<style scoped>
.MarkdownRender {
  font-size: 0.8rem;
  line-height: 1.5;
  text-wrap: pretty;

  & :deep(p),
  & :deep(ul),
  & :deep(ol),
  & :deep(blockquote),
  & :deep(pre),
  & :deep(table) {
    margin: 0;
  }

  & :deep(p + p),
  & :deep(* + ul),
  & :deep(* + ol),
  & :deep(* + blockquote),
  & :deep(* + pre),
  & :deep(* + table),
  & :deep(* + h1),
  & :deep(* + h2),
  & :deep(* + h3),
  & :deep(* + h4) {
    margin-top: 0.6em;
  }

  & :deep(h1),
  & :deep(h2),
  & :deep(h3),
  & :deep(h4) {
    font-weight: 600;
    line-height: 1.25;
  }

  & :deep(h1) {
    font-size: 1.1rem;
  }
  & :deep(h2) {
    font-size: 1rem;
  }
  & :deep(h3),
  & :deep(h4) {
    font-size: 0.9rem;
  }

  & :deep(ul),
  & :deep(ol) {
    padding-left: 1.25em;
  }

  & :deep(li + li) {
    margin-top: 0.25em;
  }

  & :deep(a) {
    color: var(--ui-primary);
    text-decoration: underline;
    text-decoration-color: var(--ui-border-accented);

    &:hover {
      text-decoration-color: currentColor;
    }
  }

  & :deep(code) {
    font-family: var(--font-mono, ui-monospace, SFMono-Regular, monospace);
    font-size: 0.9em;
    padding: 1px 4px;
    border-radius: var(--radius-sm);
    background-color: var(--ui-bg-elevated);
  }

  & :deep(pre) {
    padding: 8px 10px;
    border-radius: var(--radius-md);
    background-color: var(--ui-bg-elevated);
    overflow-x: auto;
    font-size: 0.75rem;
    line-height: 1.4;
  }

  & :deep(pre code) {
    padding: 0;
    background: none;
    font-size: inherit;
  }

  & :deep(blockquote) {
    padding-left: 0.75em;
    border-left: 2px solid var(--ui-border);
    color: var(--ui-text-muted);
  }

  & :deep(hr) {
    border: 0;
    border-top: 0.5px solid var(--ui-border);
    margin: 0.75em 0;
  }

  & :deep(img) {
    max-width: 100%;
    height: auto;
    border-radius: var(--radius-md);
  }
}
</style>
