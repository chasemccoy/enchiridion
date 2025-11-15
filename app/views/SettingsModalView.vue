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

            <ul
              v-if="syncReadwiseData?.messages && !isSyncingReadwise"
              class="SettingsModalView__syncLog"
            >
              <li
                v-for="message in syncReadwiseData?.messages"
                :key="message.timestamp"
              >
                {{ message.message }}
              </li>
            </ul>
          </li>
        </ul>
      </div>
    </template>
  </UModal>
</template>

<script setup lang="ts">
import useIntegrations from '@app/composables/useIntegrations';

const isOpen = defineModel<boolean>('isOpen', { required: true, default: false });

const { readwise } = useIntegrations();
const {
  mutate: syncReadwise,
  data: syncReadwiseData,
  isPending: isSyncingReadwise,
  reset: resetSyncReadwise,
} = readwise();

function handleSyncReadwise() {
  syncReadwise();
}

function handleAfterLeave() {
  resetSyncReadwise();
}
</script>

<style scoped>
.SettingsModalView {
  padding: 16px;
  display: grid;
  grid-template-rows: min-content;
  gap: 16px;
  min-height: 400px;
  color: var(--ui-text);
  overflow-y: auto;
  max-height: 75vh;
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
    'log log'
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

.SettingsModalView__syncLog {
  grid-area: log;
  font-size: 12px;
  color: var(--ui-text-muted);
  margin-top: 8px;
  font-family: monospace;
}
</style>
