<template>
  <UDropdownMenu
    size="sm"
    :items="menuItems"
    :ui="{
      content: 'min-w-[200px]',
    }"
    :content="{
      align: 'start',
      alignOffset: 10,
      sideOffset: 4,
    }"
  >
    <UButton
      color="neutral"
      variant="link"
      trailingIcon="i-lucide-settings"
      size="sm"
      class="PredicateSelect__button"
      :aria-label="label"
    />
  </UDropdownMenu>
</template>

<script setup lang="ts">
import {
  CANONICAL_PREDICATES,
  getPredicate,
  getInversePredicate,
  type Predicate,
} from '@shared/predicates';
import { capitalize } from '@shared/lib/formatting';
import { computed } from 'vue';

const modelValue = defineModel<string>({ default: 'related_to' });

const emit = defineEmits<{
  'select:predicate': [Predicate];
  'delete:link': [];
}>();

const { linkDirection = 'outgoing' } = defineProps<{
  linkDirection?: 'incoming' | 'outgoing';
}>();

const menuItems = computed(() => {
  const predicateItems = CANONICAL_PREDICATES.map((p) => {
    let label = capitalize(p.name);

    if (linkDirection === 'incoming') {
      const inverse = getInversePredicate(p.slug);
      label = capitalize(inverse.name);
    }

    return {
      label: capitalize(label),
      type: 'checkbox' as const,
      checked: modelValue.value === p.slug,
      onUpdateChecked(checked: boolean) {
        if (checked && p.slug !== modelValue.value) {
          modelValue.value = p.slug;
          emit('select:predicate', p);
        }
      },
    };
  });

  return [
    predicateItems,
    [
      {
        label: 'Delete',
        icon: 'i-lucide-trash',
        color: 'error',
        onSelect() {
          emit('delete:link');
        },
      },
    ],
  ];
});

const selectedPredicate = computed(() => {
  try {
    return getPredicate(modelValue.value);
  } catch {
    return null;
  }
});

const label = computed(() => {
  if (!selectedPredicate.value) return 'Predicates';

  let name = selectedPredicate.value.name;

  if (linkDirection === 'incoming') {
    const inverse = getInversePredicate(selectedPredicate.value.slug);
    name = inverse.name;
  }

  return capitalize(name);
});
</script>

<style scoped>
:global(.PredicateSelect__button) {
  gap: 2px;
}

:global(.PredicateSelect__button svg) {
  width: 14px;
  height: 14px;
  color: var(--ui-text-dimmed);
}
</style>
