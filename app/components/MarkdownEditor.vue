<template>
  <div
    ref="containerRef"
    class="MarkdownEditor"
  />
</template>

<script setup lang="ts">
import OverType from 'overtype';
import { onBeforeUnmount, onMounted, ref, watch } from 'vue';

const modelValue = defineModel<string>({ default: '' });

const { autofocus = false, placeholder } = defineProps<{
  autofocus?: boolean;
  placeholder?: string;
}>();

const enchiridionTheme = {
  name: 'enchiridion',
  colors: {
    bgPrimary: 'transparent',
    bgSecondary: 'transparent',
    text: 'var(--ui-text-highlighted)',
    textPrimary: 'var(--ui-text-highlighted)',
    textSecondary: 'var(--ui-text-muted)',
    h1: 'var(--ui-text-highlighted)',
    h2: 'var(--ui-text-highlighted)',
    h3: 'var(--ui-text-highlighted)',
    strong: 'var(--ui-text-highlighted)',
    em: 'var(--ui-text-highlighted)',
    del: 'var(--ui-text-muted)',
    link: 'var(--ui-primary)',
    code: 'var(--ui-text-highlighted)',
    codeBg: 'var(--ui-bg-accented)',
    blockquote: 'var(--ui-text-muted)',
    hr: 'var(--ui-text-muted)',
    syntaxMarker: 'var(--ui-text-dimmed)',
    syntax: 'var(--ui-text-dimmed)',
    cursor: 'var(--ui-primary)',
    selection: 'color-mix(in oklab, var(--ui-primary) 35%, transparent)',
    listMarker: 'var(--ui-text-muted)',
    rawLine: 'var(--ui-text-muted)',
    border: 'transparent',
    hoverBg: 'var(--ui-bg-accented)',
    primary: 'var(--ui-primary)',
    placeholder: 'var(--ui-text-dimmed)',
  },
  previewColors: {
    bg: 'transparent',
    text: 'var(--ui-text-highlighted)',
    h1: 'inherit',
    h2: 'inherit',
    h3: 'inherit',
    strong: 'inherit',
    em: 'inherit',
    link: 'var(--ui-primary)',
    code: 'var(--ui-text-highlighted)',
    codeBg: 'var(--ui-bg-accented)',
    blockquote: 'var(--ui-text-muted)',
    hr: 'var(--ui-text-muted)',
  },
};

const containerRef = ref<HTMLDivElement | null>(null);
let editor: ReturnType<typeof createEditor> | null = null;
let isSyncingFromModel = false;

function createEditor(target: HTMLElement) {
  const [instance] = new OverType(target, {
    toolbar: false,
    autoResize: true,
    minHeight: '120px',
    fontSize: '0.8rem',
    lineHeight: 1.5,
    padding: '0',
    value: modelValue.value ?? '',
    autofocus,
    placeholder,
    spellcheck: true,
    onChange: (value) => {
      if (isSyncingFromModel) return;
      modelValue.value = value;
    },
  });
  return instance;
}

onMounted(() => {
  if (!containerRef.value) return;
  OverType.setTheme(enchiridionTheme);
  editor = createEditor(containerRef.value);
});

onBeforeUnmount(() => {
  editor?.destroy();
  editor = null;
});

watch(
  () => modelValue.value,
  (next) => {
    if (!editor) return;
    if ((next ?? '') === editor.getValue()) return;
    isSyncingFromModel = true;
    editor.setValue(next ?? '');
    isSyncingFromModel = false;
  },
);
</script>

<style scoped>
.MarkdownEditor {
  width: 100%;
  isolation: isolate;
}

.MarkdownEditor :deep(.overtype-container),
.MarkdownEditor :deep(.overtype-wrapper) {
  background: transparent;
  border: none;
}

.MarkdownEditor :deep(.overtype-preview li.ordered-list > .syntax-marker),
.MarkdownEditor :deep(.overtype-preview li.bullet-list > .syntax-marker) {
  color: var(--ui-text-highlighted) !important;
}

.MarkdownEditor :deep(.overtype-preview a),
.MarkdownEditor :deep(.overtype-preview a:hover) {
  text-decoration: none !important;
}
</style>
