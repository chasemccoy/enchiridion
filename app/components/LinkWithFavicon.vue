<template>
  <UTooltip
    v-if="modelValue"
    :text="modelValue"
    :ui="{
      content: 'dark',
    }"
  >
    <span class="LinkWithFavicon">
      <template v-if="prefix">{{ prefix }}&nbsp;&nbsp;</template>
      <img
        v-if="faviconUrl"
        alt=""
        width="16"
        height="16"
        loading="lazy"
        decoding="async"
        :src="faviconUrl"
      />
      <a
        target="_blank"
        :href="modelValue"
      >
        {{ urlOrigin }}
      </a>
    </span>
  </UTooltip>
</template>

<script setup lang="ts">
import { getOriginOfUrl } from '@app/utils';
import { computed } from 'vue';

const modelValue = defineModel<string>({ required: true });

const { prefix } = defineProps<{
  prefix?: string;
}>();

const urlOrigin = computed(() => {
  return getOriginOfUrl(modelValue.value);
});

const faviconUrl = computed(() => {
  if (!urlOrigin.value) return null;
  return `https://www.google.com/s2/favicons?domain=${urlOrigin.value}`;
});
</script>

<style scoped>
.LinkWithFavicon {
  word-break: break-all;
  display: inline-flex;
  align-items: center;
  color: var(--ui-text-muted);
  transition: color 0.15s ease-in-out;

  & a:hover {
    color: var(--ui-text);
    text-decoration: underline;
  }

  img {
    width: 1em;
    aspect-ratio: 1;
    margin-right: 4px;
  }
}
</style>
