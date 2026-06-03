CREATE TABLE `links` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`source_id` integer NOT NULL,
	`target_id` integer NOT NULL,
	`predicate_id` integer NOT NULL,
	`notes` text,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	FOREIGN KEY (`source_id`) REFERENCES `records`(`id`) ON UPDATE cascade ON DELETE cascade,
	FOREIGN KEY (`target_id`) REFERENCES `records`(`id`) ON UPDATE cascade ON DELETE cascade,
	FOREIGN KEY (`predicate_id`) REFERENCES `predicates`(`id`) ON UPDATE cascade ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `links_source_predicate_idx` ON `links` (`source_id`,`predicate_id`);--> statement-breakpoint
CREATE INDEX `links_target_predicate_idx` ON `links` (`target_id`,`predicate_id`);--> statement-breakpoint
CREATE INDEX `links_source_idx` ON `links` (`source_id`);--> statement-breakpoint
CREATE INDEX `links_target_idx` ON `links` (`target_id`);--> statement-breakpoint
CREATE INDEX `links_predicate_idx` ON `links` (`predicate_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `links_source_target_predicate_unique` ON `links` (`source_id`,`target_id`,`predicate_id`);--> statement-breakpoint
CREATE TABLE `predicates` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`slug` text NOT NULL,
	`name` text NOT NULL,
	`type` text NOT NULL,
	`role` text,
	`inverse_slug` text,
	`canonical` integer DEFAULT true NOT NULL,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	FOREIGN KEY (`inverse_slug`) REFERENCES `predicates`(`slug`) ON UPDATE cascade ON DELETE set null
);
--> statement-breakpoint
CREATE UNIQUE INDEX `predicates_slug_unique` ON `predicates` (`slug`);--> statement-breakpoint
CREATE INDEX `predicates_id_type_idx` ON `predicates` (`id`,`type`);--> statement-breakpoint
CREATE INDEX `predicates_slug_idx` ON `predicates` (`slug`);--> statement-breakpoint
CREATE INDEX `predicates_type_idx` ON `predicates` (`type`);--> statement-breakpoint
CREATE INDEX `predicates_role_idx` ON `predicates` (`role`);--> statement-breakpoint
CREATE INDEX `predicates_canonical_idx` ON `predicates` (`canonical`);--> statement-breakpoint
CREATE INDEX `predicates_inverse_slug_idx` ON `predicates` (`inverse_slug`);--> statement-breakpoint
CREATE INDEX `predicates_type_canonical_idx` ON `predicates` (`type`,`canonical`);--> statement-breakpoint
CREATE TABLE `records` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
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
	CONSTRAINT "slug_not_empty" CHECK("records"."slug" != '')
);
--> statement-breakpoint
CREATE UNIQUE INDEX `records_slug_unique` ON `records` (`slug`);--> statement-breakpoint
CREATE INDEX `records_type_title_url_idx` ON `records` (`type`,`title`,`url`);--> statement-breakpoint
CREATE INDEX `records_slug_idx` ON `records` (`slug`);--> statement-breakpoint
CREATE INDEX `records_record_created_at_idx` ON `records` (`created_at`);--> statement-breakpoint
CREATE INDEX `records_record_updated_at_idx` ON `records` (`updated_at`);--> statement-breakpoint
CREATE INDEX `records_is_curated_idx` ON `records` (`is_curated`);--> statement-breakpoint
CREATE TABLE `media` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
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
	FOREIGN KEY (`record_id`) REFERENCES `records`(`id`) ON UPDATE cascade ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `readwise_authors` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`name` text NOT NULL,
	`origin` text,
	`record_id` integer,
	`deleted_at` text,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	FOREIGN KEY (`record_id`) REFERENCES `records`(`id`) ON UPDATE cascade ON DELETE set null
);
--> statement-breakpoint
CREATE INDEX `readwise_authors_name_idx` ON `readwise_authors` (`name`);--> statement-breakpoint
CREATE INDEX `readwise_authors_origin_idx` ON `readwise_authors` (`origin`);--> statement-breakpoint
CREATE INDEX `readwise_authors_deleted_at_idx` ON `readwise_authors` (`deleted_at`);--> statement-breakpoint
CREATE UNIQUE INDEX `readwise_authors_name_origin_unique` ON `readwise_authors` (`name`,`origin`);--> statement-breakpoint
CREATE TABLE `readwise_document_tags` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`document_id` text NOT NULL,
	`tag_id` integer NOT NULL,
	`deleted_at` text,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	FOREIGN KEY (`document_id`) REFERENCES `readwise_documents`(`id`) ON UPDATE cascade ON DELETE cascade,
	FOREIGN KEY (`tag_id`) REFERENCES `readwise_tags`(`id`) ON UPDATE cascade ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `readwise_document_tags_document_id_idx` ON `readwise_document_tags` (`document_id`);--> statement-breakpoint
CREATE INDEX `readwise_document_tags_tag_id_idx` ON `readwise_document_tags` (`tag_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `readwise_document_tags_documentId_tagId_unique` ON `readwise_document_tags` (`document_id`,`tag_id`);--> statement-breakpoint
CREATE TABLE `readwise_documents` (
	`id` text PRIMARY KEY NOT NULL,
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
	FOREIGN KEY (`author_id`) REFERENCES `readwise_authors`(`id`) ON UPDATE cascade ON DELETE set null,
	FOREIGN KEY (`parent_id`) REFERENCES `readwise_documents`(`id`) ON UPDATE cascade ON DELETE cascade,
	FOREIGN KEY (`integration_run_id`) REFERENCES `integration_runs`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`record_id`) REFERENCES `records`(`id`) ON UPDATE cascade ON DELETE set null
);
--> statement-breakpoint
CREATE INDEX `readwise_documents_parent_id_idx` ON `readwise_documents` (`parent_id`);--> statement-breakpoint
CREATE INDEX `readwise_documents_record_id_idx` ON `readwise_documents` (`record_id`);--> statement-breakpoint
CREATE INDEX `readwise_documents_author_id_idx` ON `readwise_documents` (`author_id`);--> statement-breakpoint
CREATE INDEX `readwise_documents_deleted_at_idx` ON `readwise_documents` (`deleted_at`);--> statement-breakpoint
CREATE TABLE `readwise_tags` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`tag` text NOT NULL,
	`record_id` integer,
	`deleted_at` text,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	FOREIGN KEY (`record_id`) REFERENCES `records`(`id`) ON UPDATE cascade ON DELETE set null
);
--> statement-breakpoint
CREATE UNIQUE INDEX `readwise_tags_tag_unique` ON `readwise_tags` (`tag`);--> statement-breakpoint
CREATE INDEX `readwise_tags_deleted_at_idx` ON `readwise_tags` (`deleted_at`);--> statement-breakpoint
CREATE TABLE `integration_runs` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`integration_type` text NOT NULL,
	`run_type` text DEFAULT 'sync' NOT NULL,
	`status` text DEFAULT 'in_progress' NOT NULL,
	`message` text,
	`run_start_time` text NOT NULL,
	`run_end_time` text,
	`entries_created` integer DEFAULT 0,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL
);
