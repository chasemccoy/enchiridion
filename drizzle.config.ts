import { defineConfig } from 'drizzle-kit';

export default defineConfig({
  schema: './backend/db/schema/index.ts',
  out: './backend/db/migrations',
  dialect: 'sqlite',
  dbCredentials: {
    url: 'file:enchiridion.db',
  },
});
