<template>
  <div
    class="MarkdownRender"
    v-html="html"
  />
</template>

<script setup lang="ts">
import DOMPurify from 'dompurify';
import MarkdownIt from 'markdown-it';
import markdownItMark from 'markdown-it-mark';
import { computed } from 'vue';

const { source } = defineProps<{
  source?: string | null;
}>();

const md = new MarkdownIt({
  html: false,
  linkify: true,
  breaks: true,
  typographer: true,
}).use(markdownItMark);

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
  & :deep(table),
  & :deep(h1),
  & :deep(h2),
  & :deep(h3),
  & :deep(h4),
  & :deep(hr) {
    margin: 0;
  }

  & :deep(* + p),
  & :deep(* + ul),
  & :deep(* + ol),
  & :deep(* + blockquote),
  & :deep(* + pre),
  & :deep(* + table),
  & :deep(* + h1),
  & :deep(* + h2),
  & :deep(* + h3),
  & :deep(* + h4),
  & :deep(* + hr) {
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
    padding-left: 1.5em;
  }

  & :deep(ul) {
    list-style: disc outside;
  }

  & :deep(ol) {
    list-style: decimal outside;
  }

  & :deep(li) {
    padding-left: 0.25em;
  }

  & :deep(li::marker) {
    color: var(--ui-text-muted);
  }

  & :deep(li),
  & :deep(li + li) {
    margin-top: 0.25em;
  }

  & :deep(ul li:first-child),
  & :deep(ol li:first-child) {
    margin-top: 0;
  }

  & :deep(a) {
    color: var(--ui-primary);
    text-decoration: underline;
    text-decoration-color: currentColor;
  }

  & :deep(code) {
    font-family: var(--font-mono, ui-monospace, SFMono-Regular, monospace);
    font-size: 0.9em;
    padding: 1px 4px;
    border-radius: var(--radius-sm);
    background-color: var(--ui-bg-elevated);
  }

  & :deep(mark) {
    padding: 0.22em 0.3em;
    border-radius: var(--radius-sm);
    color: light-dark(#734500, #fab219);
    background-color: light-dark(
      color-mix(in oklab, #fab219 35%, var(--ui-bg)),
      color-mix(in oklab, #fab219 15%, var(--ui-bg))
    );
    box-decoration-break: clone;
    -webkit-box-decoration-break: clone;
  }

  & :deep(pre) {
    position: relative;
    /* Left padding clears the line-number gutter rendered by ::before. */
    padding: 8px 10px 8px calc(3.2em + 4px);
    border-radius: var(--radius-md);
    background-color: var(--ui-bg-elevated);
    font-size: 0.75rem;
    line-height: 1.4;
    /* Wrap long lines instead of overflowing the container. `pre-wrap` keeps
     * the code's own newlines/indentation while wrapping overflow; `anywhere`
     * (plus min-width:0 for flex/grid parents) breaks unbreakable tokens like
     * long URLs so nothing pushes past the edge. `overflow: hidden` also trims
     * the fixed gutter below to the block's height. */
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    overflow: hidden;
    min-width: 0;
    max-width: 100%;
  }

  /* Line numbers: a hard-coded list of digits, one per line, painted into an
   * absolutely-positioned left gutter; the parent's `overflow: hidden` clips
   * the surplus to the code height. Numbers track SOURCE lines, so a wrapped
   * line shifts the code down without advancing the gutter. */
  & :deep(pre)::before {
    content: '1\A 2\A 3\A 4\A 5\A 6\A 7\A 8\A 9\A 10\A 11\A 12\A 13\A 14\A 15\A 16\A 17\A 18\A 19\A 20\A 21\A 22\A 23\A 24\A 25\A 26\A 27\A 28\A 29\A 30\A 31\A 32\A 33\A 34\A 35\A 36\A 37\A 38\A 39\A 40\A 41\A 42\A 43\A 44\A 45\A 46\A 47\A 48\A 49\A 50';
    position: absolute;
    /* Span exactly the content box (top/bottom = the pre's 8px padding) and
     * clip the surplus numbers here, so the gutter ends at the last code line
     * instead of leaking a partial number into the bottom padding. */
    top: 8px;
    bottom: 8px;
    left: 4px;
    overflow: hidden;
    width: 2.4em;
    padding-right: 0.6em;
    text-align: right;
    white-space: pre;
    font-family: var(--font-mono, ui-monospace, SFMono-Regular, monospace);
    font-variant-numeric: tabular-nums;
    color: var(--ui-text-dimmed);
    border-right: 1px solid var(--ui-border);
    user-select: none;
    pointer-events: none;
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
    border-top: 1px solid var(--ui-border-muted);
  }

  & :deep(img) {
    max-width: 100%;
    height: auto;
    border-radius: var(--radius-md);
  }
}
</style>
