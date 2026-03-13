-- Migration: Move predicates from database table to code
-- This migration:
--   1. Adds a new `predicate` text column to `links`
--   2. Populates it from the `predicates` table via `predicate_id`
--   3. Drops the old `predicate_id` column by recreating the table
--   4. Drops the `predicates` table

-- Step 1: Add the new predicate slug column
ALTER TABLE `links` ADD COLUMN `predicate` text;

-- Step 2: Populate the new column from the predicates table
UPDATE `links` SET `predicate` = (
  SELECT `slug` FROM `predicates` WHERE `predicates`.`id` = `links`.`predicate_id`
);

-- Step 3: Recreate links table without predicate_id
-- SQLite doesn't support DROP COLUMN in older versions, so we recreate the table
CREATE TABLE `links_new` (
  `id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
  `source_id` integer NOT NULL REFERENCES `records`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  `target_id` integer NOT NULL REFERENCES `records`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  `predicate` text NOT NULL,
  `notes` text,
  `record_created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
  `record_updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL
);

INSERT INTO `links_new` (`id`, `source_id`, `target_id`, `predicate`, `notes`, `record_created_at`, `record_updated_at`)
SELECT `id`, `source_id`, `target_id`, `predicate`, `notes`, `record_created_at`, `record_updated_at`
FROM `links`
WHERE `predicate` IS NOT NULL;

DROP TABLE `links`;
ALTER TABLE `links_new` RENAME TO `links`;

-- Step 4: Recreate indexes
CREATE INDEX `links_source_predicate_idx` ON `links` (`source_id`, `predicate`);
CREATE INDEX `links_target_predicate_idx` ON `links` (`target_id`, `predicate`);
CREATE INDEX `links_source_idx` ON `links` (`source_id`);
CREATE INDEX `links_target_idx` ON `links` (`target_id`);
CREATE INDEX `links_predicate_idx` ON `links` (`predicate`);
CREATE UNIQUE INDEX `links_source_target_predicate_unique` ON `links` (`source_id`, `target_id`, `predicate`);

-- Step 5: Drop the predicates table
DROP TABLE IF EXISTS `predicates`;
