<template>
  <div class="RambleView">
    <div class="RambleView__stage">
      <RambleComposer :placeholder="placeholder" />
    </div>
  </div>
</template>

<script setup lang="ts">
import RambleComposer from '@app/components/ramble/RambleComposer.vue';

const placeholder =
  'Start rambling. Type @ to reference a record, # for a concept. Paste a link to tokenize it.';
</script>

<style scoped>
.RambleView {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 48px 32px 144px;
  min-height: 100dvh;
  width: 100%;
}

.RambleView__stage {
  position: relative;
  width: 100%;
  max-width: 720px;
}
</style>
