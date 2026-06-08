CREATE TABLE `links` (
	`id` integer PRIMARY KEY AUTOINCREMENT,
	`source_id` integer NOT NULL,
	`target_id` integer NOT NULL,
	`predicate` text NOT NULL,
	`notes` text,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	CONSTRAINT `fk_links_source_id_records_id_fk` FOREIGN KEY (`source_id`) REFERENCES `records`(`id`) ON UPDATE CASCADE ON DELETE CASCADE,
	CONSTRAINT `fk_links_target_id_records_id_fk` FOREIGN KEY (`target_id`) REFERENCES `records`(`id`) ON UPDATE CASCADE ON DELETE CASCADE,
	CONSTRAINT `links_source_target_predicate_unique` UNIQUE(`source_id`,`target_id`,`predicate`)
);
--> statement-breakpoint
CREATE TABLE `records` (
	`id` integer PRIMARY KEY AUTOINCREMENT,
	`slug` text NOT NULL,
	`type` text DEFAULT 'artifact' NOT NULL,
	`title` text,
	`url` text,
	`is_curated` integer DEFAULT false NOT NULL,
	`summary` text,
	`content` text,
	`notes` text,
	`source` text,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`content_created_at` text,
	`content_updated_at` text,
	CONSTRAINT "slug_not_empty" CHECK("slug" != '')
);
--> statement-breakpoint
CREATE TABLE `media` (
	`id` integer PRIMARY KEY AUTOINCREMENT,
	`record_id` integer,
	`url` text NOT NULL,
	`alt_text` text,
	`type` text DEFAULT 'application',
	`content_type_string` text DEFAULT 'application/octet-stream' NOT NULL,
	`file_size` integer,
	`width` integer,
	`height` integer,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	CONSTRAINT `fk_media_record_id_records_id_fk` FOREIGN KEY (`record_id`) REFERENCES `records`(`id`) ON UPDATE CASCADE ON DELETE CASCADE
);
--> statement-breakpoint
CREATE TABLE `readwise_authors` (
	`id` integer PRIMARY KEY AUTOINCREMENT,
	`name` text NOT NULL,
	`origin` text,
	`record_id` integer,
	`deleted_at` text,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	CONSTRAINT `fk_readwise_authors_record_id_records_id_fk` FOREIGN KEY (`record_id`) REFERENCES `records`(`id`) ON UPDATE CASCADE ON DELETE SET NULL,
	CONSTRAINT `readwise_authors_name_origin_unique` UNIQUE(`name`,`origin`)
);
--> statement-breakpoint
CREATE TABLE `readwise_document_tags` (
	`id` integer PRIMARY KEY AUTOINCREMENT,
	`document_id` text NOT NULL,
	`tag_id` integer NOT NULL,
	`deleted_at` text,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	CONSTRAINT `fk_readwise_document_tags_document_id_readwise_documents_id_fk` FOREIGN KEY (`document_id`) REFERENCES `readwise_documents`(`id`) ON UPDATE CASCADE ON DELETE CASCADE,
	CONSTRAINT `fk_readwise_document_tags_tag_id_readwise_tags_id_fk` FOREIGN KEY (`tag_id`) REFERENCES `readwise_tags`(`id`) ON UPDATE CASCADE ON DELETE CASCADE,
	CONSTRAINT `readwise_document_tags_document_id_tag_id_unique` UNIQUE(`document_id`,`tag_id`)
);
--> statement-breakpoint
CREATE TABLE `readwise_documents` (
	`id` text PRIMARY KEY,
	`url` text NOT NULL,
	`source_url` text,
	`title` text,
	`author` text,
	`author_id` integer,
	`source` text,
	`content` text,
	`html_content` text,
	`category` text,
	`location` text,
	`tags` text,
	`site_name` text,
	`word_count` integer,
	`notes` text,
	`summary` text,
	`image_url` text,
	`parent_id` text,
	`reading_progress` integer,
	`published_date` text,
	`first_opened_at` text,
	`last_opened_at` text,
	`saved_at` text NOT NULL,
	`last_moved_at` text NOT NULL,
	`integration_run_id` integer NOT NULL,
	`record_id` integer,
	`deleted_at` text,
	`content_created_at` text,
	`content_updated_at` text,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	CONSTRAINT `fk_readwise_documents_author_id_readwise_authors_id_fk` FOREIGN KEY (`author_id`) REFERENCES `readwise_authors`(`id`) ON UPDATE CASCADE ON DELETE SET NULL,
	CONSTRAINT `fk_readwise_documents_parent_id_readwise_documents_id_fk` FOREIGN KEY (`parent_id`) REFERENCES `readwise_documents`(`id`) ON UPDATE CASCADE ON DELETE CASCADE,
	CONSTRAINT `fk_readwise_documents_integration_run_id_integration_runs_id_fk` FOREIGN KEY (`integration_run_id`) REFERENCES `integration_runs`(`id`),
	CONSTRAINT `fk_readwise_documents_record_id_records_id_fk` FOREIGN KEY (`record_id`) REFERENCES `records`(`id`) ON UPDATE CASCADE ON DELETE SET NULL
);
--> statement-breakpoint
CREATE TABLE `readwise_tags` (
	`id` integer PRIMARY KEY AUTOINCREMENT,
	`tag` text NOT NULL UNIQUE,
	`record_id` integer,
	`deleted_at` text,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	CONSTRAINT `fk_readwise_tags_record_id_records_id_fk` FOREIGN KEY (`record_id`) REFERENCES `records`(`id`) ON UPDATE CASCADE ON DELETE SET NULL
);
--> statement-breakpoint
CREATE TABLE `integration_runs` (
	`id` integer PRIMARY KEY AUTOINCREMENT,
	`integration_type` text NOT NULL,
	`run_type` text DEFAULT 'sync' NOT NULL,
	`status` text DEFAULT 'in_progress' NOT NULL,
	`message` text,
	`run_start_time` text NOT NULL,
	`run_end_time` text,
	`entries_created` integer DEFAULT 0,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL
);
--> statement-breakpoint
CREATE INDEX `links_source_predicate_idx` ON `links` (`source_id`,`predicate`);--> statement-breakpoint
CREATE INDEX `links_target_predicate_idx` ON `links` (`target_id`,`predicate`);--> statement-breakpoint
CREATE INDEX `links_source_idx` ON `links` (`source_id`);--> statement-breakpoint
CREATE INDEX `links_target_idx` ON `links` (`target_id`);--> statement-breakpoint
CREATE INDEX `links_predicate_idx` ON `links` (`predicate`);--> statement-breakpoint
CREATE INDEX `records_type_title_url_idx` ON `records` (`type`,`title`,`url`);--> statement-breakpoint
CREATE UNIQUE INDEX `records_slug_idx` ON `records` (`slug`);--> statement-breakpoint
CREATE INDEX `records_record_created_at_idx` ON `records` (`created_at`);--> statement-breakpoint
CREATE INDEX `records_record_updated_at_idx` ON `records` (`updated_at`);--> statement-breakpoint
CREATE INDEX `records_is_curated_idx` ON `records` (`is_curated`);--> statement-breakpoint
CREATE INDEX `media_record_id_idx` ON `media` (`record_id`);--> statement-breakpoint
CREATE INDEX `readwise_authors_name_idx` ON `readwise_authors` (`name`);--> statement-breakpoint
CREATE INDEX `readwise_authors_origin_idx` ON `readwise_authors` (`origin`);--> statement-breakpoint
CREATE INDEX `readwise_authors_deleted_at_idx` ON `readwise_authors` (`deleted_at`);--> statement-breakpoint
CREATE INDEX `readwise_document_tags_document_id_idx` ON `readwise_document_tags` (`document_id`);--> statement-breakpoint
CREATE INDEX `readwise_document_tags_tag_id_idx` ON `readwise_document_tags` (`tag_id`);--> statement-breakpoint
CREATE INDEX `readwise_documents_parent_id_idx` ON `readwise_documents` (`parent_id`);--> statement-breakpoint
CREATE INDEX `readwise_documents_record_id_idx` ON `readwise_documents` (`record_id`);--> statement-breakpoint
CREATE INDEX `readwise_documents_author_id_idx` ON `readwise_documents` (`author_id`);--> statement-breakpoint
CREATE INDEX `readwise_documents_deleted_at_idx` ON `readwise_documents` (`deleted_at`);--> statement-breakpoint
CREATE INDEX `readwise_tags_deleted_at_idx` ON `readwise_tags` (`deleted_at`);