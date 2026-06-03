PRAGMA defer_foreign_keys = ON;--> statement-breakpoint
CREATE TABLE `__new_links` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`source_id` integer NOT NULL,
	`target_id` integer NOT NULL,
	`predicate` text NOT NULL,
	`notes` text,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	FOREIGN KEY (`source_id`) REFERENCES `records`(`id`) ON UPDATE cascade ON DELETE cascade,
	FOREIGN KEY (`target_id`) REFERENCES `records`(`id`) ON UPDATE cascade ON DELETE cascade
);
--> statement-breakpoint
INSERT INTO `__new_links` (`id`, `source_id`, `target_id`, `predicate`, `notes`, `created_at`, `updated_at`)
SELECT `links`.`id`, `links`.`source_id`, `links`.`target_id`, `predicates`.`slug`, `links`.`notes`, `links`.`created_at`, `links`.`updated_at`
FROM `links`
JOIN `predicates` ON `predicates`.`id` = `links`.`predicate_id`;
--> statement-breakpoint
DROP TABLE `links`;--> statement-breakpoint
ALTER TABLE `__new_links` RENAME TO `links`;--> statement-breakpoint
CREATE INDEX `links_source_predicate_idx` ON `links` (`source_id`,`predicate`);--> statement-breakpoint
CREATE INDEX `links_target_predicate_idx` ON `links` (`target_id`,`predicate`);--> statement-breakpoint
CREATE INDEX `links_source_idx` ON `links` (`source_id`);--> statement-breakpoint
CREATE INDEX `links_target_idx` ON `links` (`target_id`);--> statement-breakpoint
CREATE INDEX `links_predicate_idx` ON `links` (`predicate`);--> statement-breakpoint
CREATE UNIQUE INDEX `links_source_target_predicate_unique` ON `links` (`source_id`,`target_id`,`predicate`);--> statement-breakpoint
DROP INDEX IF EXISTS `predicates_slug_unique`;--> statement-breakpoint
DROP INDEX IF EXISTS `predicates_id_type_idx`;--> statement-breakpoint
DROP INDEX IF EXISTS `predicates_slug_idx`;--> statement-breakpoint
DROP INDEX IF EXISTS `predicates_type_idx`;--> statement-breakpoint
DROP INDEX IF EXISTS `predicates_role_idx`;--> statement-breakpoint
DROP INDEX IF EXISTS `predicates_canonical_idx`;--> statement-breakpoint
DROP INDEX IF EXISTS `predicates_inverse_slug_idx`;--> statement-breakpoint
DROP INDEX IF EXISTS `predicates_type_canonical_idx`;--> statement-breakpoint
DROP TABLE `predicates`;
