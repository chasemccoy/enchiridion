<template>
  <UModal
    v-model:open="isOpen"
    title="Settings"
    @after:leave="handleAfterLeave"
  >
    <template #content>
      <div class="SettingsModalView">
        <h2 class="SettingsModalView__title">Integrations</h2>

        <ul class="SettingsModalView__integrations">
          <li class="SettingsModalView__integration">
            <h3 class="SettingsModalView__subtitle">Readwise</h3>
            <p class="SettingsModalView__integrationDescription">
              Sync your recent Readwise highlights to the database.
            </p>

            <UButton
              class="SettingsModalView__button"
              color="neutral"
              variant="outline"
              icon="i-lucide-refresh-cw"
              :label="isSyncingReadwise ? 'Syncing…' : 'Sync'"
              :loading="isSyncingReadwise"
              @click="handleSyncReadwise"
            />

            <SyncReport
              v-if="readwise.status.value !== 'idle'"
              class="SettingsModalView__syncReport"
              :status="readwise.status.value"
              :phases="readwise.phases.value"
              :records="readwise.records.value"
              :links="readwise.links.value"
              :log="readwise.log.value"
              :warnings="readwise.warnings.value"
              :done="readwise.done.value"
              :error="readwise.error.value"
            />
          </li>
        </ul>
      </div>
    </template>
  </UModal>
</template>

<script setup lang="ts">
import SyncReport from '@app/components/SyncReport.vue';
import useReadwiseSync from '@app/composables/useReadwiseSync';
import { computed } from 'vue';

const isOpen = defineModel<boolean>('isOpen', { required: true, default: false });

const readwise = useReadwiseSync();
const isSyncingReadwise = computed(() => readwise.status.value === 'running');

function handleSyncReadwise() {
  readwise.run();
}

function handleAfterLeave() {
  // Leaves a running sync alone so reopening the panel picks it back up;
  // reset() is a no-op mid-run.
  readwise.reset();
}
</script>

<style scoped>
.SettingsModalView {
  padding: 16px;
  display: grid;
  grid-template-rows: min-content;
  gap: 16px;
  /* Cap to the smaller of 400px and the viewport so short phones (and landscape)
   * don't overflow; dvh tracks mobile browser chrome. */
  min-height: min(400px, 60dvh);
  color: var(--ui-text);
  overflow-y: auto;
  max-height: 75dvh;
}

.SettingsModalView__title {
  font-size: 18px;
  font-weight: bold;
  border-bottom: 1px solid var(--ui-border);
  padding-bottom: 6px;
}

.SettingsModalView__integration {
  display: grid;
  grid-template:
    'title button'
    'description button'
    'report report'
    / 1fr min-content;
  column-gap: 16px;
  align-items: center;
}

.SettingsModalView__subtitle {
  grid-area: title;
  font-weight: bold;
}

.SettingsModalView__integrationDescription {
  grid-area: description;
  font-size: 14px;
  color: var(--ui-text-muted);
  text-wrap: pretty;
}

:deep(.SettingsModalView__button) {
  grid-area: button;

  & svg {
    width: 16px;
  }
}

.SettingsModalView__syncReport {
  grid-area: report;
  margin-top: 14px;
  padding-top: 14px;
  border-top: 1px solid var(--ui-border);
}
</style>
