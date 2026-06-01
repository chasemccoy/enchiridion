import { defineConfig } from 'drizzle-kit';

export default defineConfig({
  schema: './backend/db/schema/index.ts',
  out: './backend/db/migrations',
  dialect: 'sqlite',
  dbCredentials: {
    url: 'file:enchiridion.db',
  },
  // The sqlite-vec tables (`vec_records`, `vec_records_meta`, and the vec0
  // shadow tables) are created at runtime in backend/db/index.ts, not via
  // Drizzle. Exclude them so `db:push` never tries to drop them.
  tablesFilter: ['!vec_*'],
});
