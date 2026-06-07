<template>
  <div class="V32">
    <RecordHero3 editStyle="panel" />
    <LinkedRecordsGrouped />
  </div>
</template>

<script setup lang="ts">
import RecordHero3 from './RecordHero3.vue';
import LinkedRecordsGrouped from './LinkedRecordsGrouped.vue';
</script>

<style scoped>
.V32 {
  display: grid;
  gap: 24px;
  max-width: 800px;
  margin: 0 auto;
}
</style>
