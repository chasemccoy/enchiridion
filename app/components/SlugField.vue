<template>
  <UFieldGroup class="SlugField">
    <UBadge
      color="neutral"
      variant="outline"
      size="lg"
      label="Slug"
      class="SlugField__badge"
    />

    <UInput
      v-model="modelValue"
      class="SlugField__field"
      variant="outline"
      placeholder="record-slug"
      :ui="{
        base: 'SlugField__input',
      }"
      :readonly
      required
    />
  </UFieldGroup>
</template>

<script setup lang="ts">
import { slugify } from '@shared/lib/formatting';

const modelValue = defineModel<string>({
  required: true,
  set(value) {
    return slugify(value);
  },
});

const { readonly = false } = defineProps<{
  readonly?: boolean;
}>();
</script>

<style scoped>
.SlugField__badge {
  min-width: var(--combinedFieldMinBadgeWidth);
}

:global(.SlugField__input) {
  color: var(--ui-text-muted);
}

:global(.SlugField__input:hover),
:global(.SlugField__input:focus) {
  color: var(--ui-text);
}
</style>
