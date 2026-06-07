<template>
  <div class="V4Tune">
    <RecordHero />
    <LinkedRecordsGrouped />
  </div>
</template>

<script setup lang="ts">
import RecordHero from './RecordHero.vue';
import LinkedRecordsGrouped from './LinkedRecordsGrouped.vue';
</script>

<style scoped>
.V4Tune {
  display: grid;
  gap: 24px;
  max-width: 800px;
  margin: 0 auto;
}
</style>
