CREATE TABLE `archives` (
	`id` integer PRIMARY KEY AUTOINCREMENT,
	`record_id` integer NOT NULL,
	`url` text NOT NULL,
	`path` text,
	`status` text NOT NULL,
	`title` text,
	`error` text,
	`archived_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	CONSTRAINT `fk_archives_record_id_records_id_fk` FOREIGN KEY (`record_id`) REFERENCES `records`(`id`) ON UPDATE CASCADE ON DELETE CASCADE
);
--> statement-breakpoint
CREATE UNIQUE INDEX `archives_record_id_idx` ON `archives` (`record_id`);