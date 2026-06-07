<template>
  <div class="V31">
    <RecordHero3 editStyle="inline" />
    <LinkedRecordsGrouped />
  </div>
</template>

<script setup lang="ts">
import RecordHero3 from './RecordHero3.vue';
import LinkedRecordsGrouped from './LinkedRecordsGrouped.vue';
</script>

<style scoped>
.V31 {
  display: grid;
  gap: 24px;
  max-width: 800px;
  margin: 0 auto;
}
</style>
