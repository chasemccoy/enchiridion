<template>
  <div class="CombinedFields">
    <slot />
  </div>
</template>

<style scoped>
.CombinedFields {
  display: grid;
  border-radius: var(--radius-xl);
  overflow: hidden;
  border: 1px solid var(--ui-border);

  --ui-radius: 0;

  &:focus-within {
    border-color: var(--ui-border-accented);
  }

  & :deep(input),
  & :deep(textarea),
  & :deep(span) {
    box-shadow: none;
  }

  & > * + * {
    border-top: 1px solid var(--ui-border);
  }

  & :deep(.Badge) {
    min-width: var(--combinedFieldMinBadgeWidth);
  }
}
</style>
