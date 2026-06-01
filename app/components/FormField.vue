<template>
  <label class="FormField">
    <div class="FormField__label">{{ label }}</div>
    <slot />
  </label>
</template>

<script setup lang="ts">
defineProps<{ label: string }>();
</script>

<style scoped>
.FormField {
  display: grid;
  gap: 6px;
}

.FormField__label {
  font-weight: var(--font-weight-medium);
  font-size: var(--font-size-label);
}
</style>
