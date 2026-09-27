/* eslint-disable no-console */
/**
 * One-time migration: move record archives out of their per-record subfolders
 * (`<ARCHIVE_DIR>/<recordId>/<slug>/`) into the flat `<ARCHIVE_DIR>/<slug>/`
 * layout amber's CLI and library use, and rewrite the archive rows to match.
 *
 * Dry run by default; pass --apply to move folders and update rows.
 *
 *   pnpm archive:flatten                    # report what would move
 *   pnpm archive:flatten --apply            # do it
 *   pnpm archive:flatten --from=<old root>  # rows live under a different root
 *                                           # than ARCHIVE_DIR now points at
 *
 * A folder whose flat destination already exists is left where it is (that is
 * exactly the collision case the per-record layout still exists for); the
 * report names it. Rerunning is safe: rows already flat are skipped.
 */
import 'dotenv/config';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { eq } from 'drizzle-orm';
import { db } from '@db/index';
import { archives } from '@db/schema';
import { archiveRoot } from '@integrations/archive';

const apply = process.argv.includes('--apply');
const root = archiveRoot();
const fromRoot = process.argv.find((a) => a.startsWith('--from='))?.slice('--from='.length) || root;

const rows = await db.select().from(archives);
let moved = 0;
let skipped = 0;

for (const row of rows) {
  const match = row.path?.match(/^(\d+)\/(.+)$/);
  if (!match) continue;

  const [, id, slug] = match;
  const from = path.join(fromRoot, row.path!);
  const to = path.join(root, slug!);

  if (!fs.existsSync(from)) {
    console.log(`skip  record ${row.recordId}: ${row.path} is not on disk`);
    skipped++;
    continue;
  }
  if (fs.existsSync(to)) {
    console.log(
      `skip  record ${row.recordId}: ${slug} already exists at the root, leaving ${row.path}`,
    );
    skipped++;
    continue;
  }

  console.log(`${apply ? 'move ' : 'would'} record ${row.recordId}: ${row.path} -> ${slug}`);
  if (apply) {
    fs.renameSync(from, to);
    await db.update(archives).set({ path: slug }).where(eq(archives.id, row.id));
    const parent = path.join(fromRoot, id!);
    if (fs.existsSync(parent) && fs.readdirSync(parent).length === 0) fs.rmdirSync(parent);
  }
  moved++;
}

console.log(
  `${apply ? 'moved' : 'would move'} ${moved}, skipped ${skipped}, ${rows.length - moved - skipped} already flat` +
    (apply ? '' : ' (dry run; pass --apply)'),
);
