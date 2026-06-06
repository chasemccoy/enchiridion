<template>
  <div
    ref="editorEl"
    class="RambleEditor"
    :class="{ 'RambleEditor--empty': isEmpty }"
    :data-placeholder="placeholder"
    contenteditable="true"
    spellcheck="true"
    @input="handleInput"
    @keydown="handleKeydown"
    @paste="handlePaste"
    @blur="handleBlur"
    @click="handleClick"
  />
</template>

<script setup lang="ts">
import { hostnameOf, isUrl } from '@app/lib/ramble/draftFromEditor';
import {
  RAMBLE_DEFAULT_PREDICATE,
  type PredicateSlug,
  type RambleTrigger,
} from '@shared/types/ramble';
import { nextTick, onMounted, ref } from 'vue';

import type { MentionMenuItem } from './RambleMentionMenu.vue';

export type TriggerState = {
  query: string;
  trigger: RambleTrigger;
  rect: { top: number; left: number };
  /** Where the trigger char lives — used internally to slice the query out. */
  triggerNode: Text;
  triggerOffset: number;
};

export type MentionKey = 'up' | 'down' | 'enter' | 'tab' | 'esc';

const props = defineProps<{
  placeholder: string;
}>();

const emit = defineEmits<{
  /** Fires after any DOM change so the parent can recompute the draft. */
  change: [];
  'trigger-update': [TriggerState | null];
  'mention-key': [MentionKey];
  /** A pill was clicked. The parent decides which menu to open. */
  'pill-click': [HTMLElement];
}>();

const editorEl = ref<HTMLDivElement | null>(null);
const isEmpty = ref(true);

const MAX_QUERY_LENGTH = 60;

onMounted(() => {
  editorEl.value?.focus();
  refreshEmpty();
});

function refreshEmpty() {
  const el = editorEl.value;
  if (!el) return;
  const hasText = (el.textContent ?? '').trim().length > 0;
  const hasPill = el.querySelector('[data-pill]') !== null;
  isEmpty.value = !hasText && !hasPill;
}

function notifyChange() {
  refreshEmpty();
  emit('change');
}

function handleInput() {
  notifyChange();
  detectMentionTrigger();
}

function handleBlur() {
  // Defer so a click on a menu item still fires before we tear down trigger
  // state and the menu closes.
  setTimeout(() => {
    if (document.activeElement !== editorEl.value) {
      emit('trigger-update', null);
    }
  }, 120);
}

function handleClick(event: MouseEvent) {
  const target = event.target;
  if (!(target instanceof HTMLElement)) return;
  const pill = target.closest('[data-pill]');
  if (!pill || !(pill instanceof HTMLElement) || !editorEl.value?.contains(pill)) return;
  event.preventDefault();
  emit('pill-click', pill);
}

function handleKeydown(event: KeyboardEvent) {
  // When a mention trigger is active, intercept menu-navigation keys and
  // let the parent (which owns the menu state) react.
  const triggerIsActive = currentTriggerState !== null;
  if (triggerIsActive) {
    const mapped = mapMentionKey(event);
    if (mapped) {
      event.preventDefault();
      emit('mention-key', mapped);
      return;
    }
  }

  // Backspace at the leading edge of a text node after a pill: nuke the
  // pill in one keystroke instead of leaving a stranded wrapper.
  if (event.key === 'Backspace') {
    const sel = window.getSelection();
    if (sel && sel.isCollapsed && sel.rangeCount > 0) {
      const range = sel.getRangeAt(0);
      const { startContainer, startOffset } = range;
      if (startContainer.nodeType === Node.TEXT_NODE && startOffset === 0) {
        const prev = (startContainer as Text).previousSibling;
        if (prev instanceof HTMLElement && prev.dataset.pill) {
          event.preventDefault();
          prev.remove();
          notifyChange();
        }
      }
    }
  }
}

function mapMentionKey(event: KeyboardEvent): MentionKey | null {
  switch (event.key) {
    case 'ArrowDown':
      return 'down';
    case 'ArrowUp':
      return 'up';
    case 'Enter':
      return 'enter';
    case 'Tab':
      return 'tab';
    case 'Escape':
      return 'esc';
    default:
      return null;
  }
}

function handlePaste(event: ClipboardEvent) {
  const text = event.clipboardData?.getData('text/plain') ?? '';
  if (!text) return;
  event.preventDefault();
  const trimmed = text.trim();
  if (isUrl(trimmed)) {
    insertLinkPill(trimmed);
  } else {
    insertPlainText(text);
  }
}

function insertPlainText(text: string) {
  const sel = window.getSelection();
  if (!sel || sel.rangeCount === 0) return;
  const range = sel.getRangeAt(0);
  range.deleteContents();
  range.insertNode(document.createTextNode(text));
  range.collapse(false);
  sel.removeAllRanges();
  sel.addRange(range);
  notifyChange();
  detectMentionTrigger();
}

function insertLinkPill(url: string) {
  const sel = window.getSelection();
  if (!sel || sel.rangeCount === 0) return;
  const pill = buildLinkPill(url);
  const range = sel.getRangeAt(0);
  range.deleteContents();
  range.insertNode(pill);
  insertSpaceAfter(pill);
  notifyChange();
}

function buildLinkPill(url: string): HTMLElement {
  const span = document.createElement('span');
  span.className = 'RambleEditor__pill RambleEditor__pill--link';
  span.contentEditable = 'false';
  span.dataset.pill = 'link';
  span.dataset.url = url;
  span.title = url;
  renderLinkPillContent(span, url);
  return span;
}

function renderLinkPillContent(pill: HTMLElement, url: string) {
  // Favicon + truncated hostname. Favicon stays outside the label span so it
  // keeps its fixed size even when the label is ellipsized.
  pill.textContent = '';
  const host = hostnameOf(url);
  const favicon = document.createElement('img');
  favicon.className = 'RambleEditor__pillFavicon';
  favicon.src = `https://www.google.com/s2/favicons?domain=${host}&sz=32`;
  favicon.alt = '';
  pill.appendChild(favicon);
  const label = document.createElement('span');
  label.className = 'RambleEditor__pillLabel';
  label.textContent = host;
  pill.appendChild(label);
}

function buildMentionPill(item: MentionMenuItem, trigger: RambleTrigger): HTMLElement {
  const span = document.createElement('span');
  // # triggers always produce concept pills; @ uses neutral mention styling
  // even when the selection happens to be a concept (the visual mirrors the
  // user's intent, broad reference vs tagged concept).
  const variant = trigger === '#' ? 'concept' : 'mention';
  span.className = `RambleEditor__pill RambleEditor__pill--${variant}`;
  span.contentEditable = 'false';
  span.dataset.pill = variant;
  span.dataset.recordId = String(item.id);
  span.dataset.slug = item.slug;
  span.dataset.type = item.type;
  span.dataset.label = item.label;
  span.dataset.trigger = trigger;
  span.dataset.predicate = RAMBLE_DEFAULT_PREDICATE[trigger];
  renderPillText(span);
  return span;
}

function renderPillText(pill: HTMLElement) {
  const label = pill.dataset.label ?? pill.textContent ?? '';
  const trigger = pill.dataset.trigger as RambleTrigger | undefined;
  // Predicate lives in data attrs only — surfaces via the click menu, not
  // inside the pill text. # pills keep their prefix as a visual hint.
  // Wrap in an inner span so we can truncate with ellipsis while keeping the
  // pill itself baseline-aligned (overflow:hidden on the pill shifts its
  // inline-flex baseline to the bottom margin edge).
  pill.textContent = '';
  const inner = document.createElement('span');
  inner.className = 'RambleEditor__pillLabel';
  inner.textContent = trigger === '#' ? `#${label}` : label;
  pill.appendChild(inner);
}

function insertSpaceAfter(pill: HTMLElement) {
  const space = document.createTextNode(' ');
  pill.after(space);
  const sel = window.getSelection();
  if (!sel) return;
  const after = document.createRange();
  after.setStart(space, space.length);
  after.collapse(true);
  sel.removeAllRanges();
  sel.addRange(after);
}

// ─── Trigger detection ─────────────────────────────────────────────────────

let currentTriggerState: TriggerState | null = null;

function detectMentionTrigger() {
  const next = computeTriggerState();
  currentTriggerState = next;
  emit('trigger-update', next);
}

function computeTriggerState(): TriggerState | null {
  const sel = window.getSelection();
  if (!sel || sel.rangeCount === 0 || !sel.isCollapsed) return null;
  const range = sel.getRangeAt(0);
  const { startContainer, startOffset } = range;
  if (startContainer.nodeType !== Node.TEXT_NODE) return null;
  const textNode = startContainer as Text;
  const text = textNode.textContent ?? '';

  let i = startOffset - 1;
  const minIndex = Math.max(-1, startOffset - 1 - MAX_QUERY_LENGTH);
  while (i > minIndex) {
    const ch = text[i]!;
    if (ch === '@' || ch === '#') break;
    if (ch === '\n') return null;
    i -= 1;
  }
  if (i < 0 || (text[i] !== '@' && text[i] !== '#')) return null;
  // Trigger must be at start of node or preceded by whitespace ("C#7" / "name@x"
  // don't count).
  if (i > 0 && !/\s/.test(text[i - 1]!)) return null;

  const trigger = text[i] as RambleTrigger;
  const query = text.slice(i + 1, startOffset);

  const measureRange = document.createRange();
  measureRange.setStart(textNode, i);
  measureRange.setEnd(textNode, i + 1);
  const rect = measureRange.getClientRects()[0];
  if (!rect) return null;

  const editorRect = editorEl.value?.getBoundingClientRect();
  const right = editorRect?.right ?? window.innerWidth;

  return {
    query,
    trigger,
    triggerNode: textNode,
    triggerOffset: i,
    rect: {
      top: rect.bottom + 6,
      left: Math.min(rect.left, right - 360),
    },
  };
}

// ─── Imperative API (called by the parent) ────────────────────────────────

function commitMention(item: MentionMenuItem) {
  const state = currentTriggerState;
  if (!state) return;
  const node = state.triggerNode;
  const start = state.triggerOffset;
  const caret = window.getSelection()?.getRangeAt(0).startOffset ?? start + 1;
  const text = node.textContent ?? '';
  const range = document.createRange();
  range.setStart(node, start);
  range.setEnd(node, Math.max(caret, start));
  if (range.endOffset > text.length) {
    currentTriggerState = null;
    emit('trigger-update', null);
    return;
  }
  range.deleteContents();
  const pill = buildMentionPill(item, state.trigger);
  range.insertNode(pill);
  insertSpaceAfter(pill);

  currentTriggerState = null;
  emit('trigger-update', null);
  notifyChange();
  nextTick(() => editorEl.value?.focus());
}

function dismissTrigger() {
  if (!currentTriggerState) return;
  currentTriggerState = null;
  emit('trigger-update', null);
}

function updatePillPredicate(pill: HTMLElement, predicate: PredicateSlug) {
  pill.dataset.predicate = predicate;
  renderPillText(pill);
  notifyChange();
}

function updateLinkPill(pill: HTMLElement, url: string) {
  pill.dataset.url = url;
  pill.title = url;
  renderLinkPillContent(pill, url);
  notifyChange();
}

function getElement(): HTMLDivElement | null {
  return editorEl.value;
}

function focus() {
  editorEl.value?.focus();
}

defineExpose({
  commitMention,
  dismissTrigger,
  updatePillPredicate,
  updateLinkPill,
  getElement,
  focus,
});

// Surface the `placeholder` prop for the v-bind in the template. (Otherwise
// TS thinks it's unused even though the template references it.)
void props.placeholder;
</script>

<style scoped>
.RambleEditor {
  position: relative;
  width: 100%;
  outline: none;
  font-family: var(--font-serif, 'Georgia', serif);
  font-size: 1.5rem;
  line-height: 1.55;
  color: var(--ui-text-highlighted);
  caret-color: var(--ui-primary);
  white-space: pre-wrap;
  word-break: break-word;
  min-height: 6em;
}

.RambleEditor--empty::before {
  content: attr(data-placeholder);
  position: absolute;
  top: 0;
  left: 0;
  color: var(--ui-text-dimmed);
  pointer-events: none;
  user-select: none;
}

.RambleEditor :deep(.RambleEditor__pill) {
  display: inline-flex;
  align-items: baseline;
  padding: 0.05em 0.5em;
  margin: 0 0.05em;
  border-radius: 999px;
  font-family: var(--font-sans, sans-serif);
  font-size: 0.82em;
  line-height: 1.4;
  vertical-align: baseline;
  cursor: pointer;
  user-select: none;
  transform: translateY(-0.08em);
  /* Cap chips so a long-titled record doesn't dominate a line. Truncation
   * lives on the inner span so the pill itself keeps its baseline. */
  max-width: 50%;
}

.RambleEditor :deep(.RambleEditor__pillLabel) {
  display: inline-block;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.RambleEditor :deep(.RambleEditor__pill--link) {
  padding-left: 0.25em;
  gap: 0.3em;
}

.RambleEditor :deep(.RambleEditor__pillFavicon) {
  flex: none;
  width: 0.95em;
  height: 0.95em;
  border-radius: 999px;
  align-self: center;
  object-fit: cover;
}

.RambleEditor :deep(.RambleEditor__pill--mention) {
  background-color: var(--ui-bg-accented);
  color: var(--ui-text);
  border: 0.5px solid var(--ui-border-accented);
}

.RambleEditor :deep(.RambleEditor__pill--concept) {
  background: linear-gradient(
    135deg,
    color-mix(in oklab, oklch(0.72 0.18 60) 25%, transparent),
    color-mix(in oklab, oklch(0.72 0.18 60) 10%, transparent)
  );
  color: oklch(0.72 0.18 60);
  border: 0.5px solid color-mix(in oklab, oklch(0.72 0.18 60) 40%, transparent);
}

.RambleEditor :deep(.RambleEditor__pill--link) {
  background: linear-gradient(
    135deg,
    color-mix(in oklab, var(--ui-primary) 22%, transparent),
    color-mix(in oklab, var(--ui-primary) 8%, transparent)
  );
  color: var(--ui-primary);
  border: 0.5px solid color-mix(in oklab, var(--ui-primary) 35%, transparent);
}
</style>
