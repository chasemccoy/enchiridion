-- Index: links_predicate_idx
CREATE INDEX `links_predicate_idx` ON `links` (`predicate`);

-- Index: links_source_idx
CREATE INDEX `links_source_idx` ON `links` (`source_id`);

-- Index: links_source_predicate_idx
CREATE INDEX `links_source_predicate_idx` ON `links` (`source_id`,`predicate`);

-- Index: links_source_target_predicate_unique
CREATE UNIQUE INDEX `links_source_target_predicate_unique` ON `links` (`source_id`,`target_id`,`predicate`);

-- Index: links_target_idx
CREATE INDEX `links_target_idx` ON `links` (`target_id`);

-- Index: links_target_predicate_idx
CREATE INDEX `links_target_predicate_idx` ON `links` (`target_id`,`predicate`);

-- Index: media_record_id_idx
CREATE INDEX `media_record_id_idx` ON `media` (`record_id`);

-- Index: readwise_authors_deleted_at_idx
CREATE INDEX `readwise_authors_deleted_at_idx` ON `readwise_authors` (`deleted_at`);

-- Index: readwise_authors_name_idx
CREATE INDEX `readwise_authors_name_idx` ON `readwise_authors` (`name`);

-- Index: readwise_authors_origin_idx
CREATE INDEX `readwise_authors_origin_idx` ON `readwise_authors` (`origin`);

-- Index: readwise_document_tags_document_id_idx
CREATE INDEX `readwise_document_tags_document_id_idx` ON `readwise_document_tags` (`document_id`);

-- Index: readwise_document_tags_tag_id_idx
CREATE INDEX `readwise_document_tags_tag_id_idx` ON `readwise_document_tags` (`tag_id`);

-- Index: readwise_documents_author_id_idx
CREATE INDEX `readwise_documents_author_id_idx` ON `readwise_documents` (`author_id`);

-- Index: readwise_documents_deleted_at_idx
CREATE INDEX `readwise_documents_deleted_at_idx` ON `readwise_documents` (`deleted_at`);

-- Index: readwise_documents_parent_id_idx
CREATE INDEX `readwise_documents_parent_id_idx` ON `readwise_documents` (`parent_id`);

-- Index: readwise_documents_record_id_idx
CREATE INDEX `readwise_documents_record_id_idx` ON `readwise_documents` (`record_id`);

-- Index: readwise_tags_deleted_at_idx
CREATE INDEX `readwise_tags_deleted_at_idx` ON `readwise_tags` (`deleted_at`);

-- Index: records_is_curated_idx
CREATE INDEX `records_is_curated_idx` ON `records` (`is_curated`);

-- Index: records_record_created_at_idx
CREATE INDEX `records_record_created_at_idx` ON `records` (`created_at`);

-- Index: records_record_updated_at_idx
CREATE INDEX `records_record_updated_at_idx` ON `records` (`updated_at`);

-- Index: records_slug_idx
CREATE UNIQUE INDEX `records_slug_idx` ON `records` (`slug`);

-- Index: records_type_title_url_idx
CREATE INDEX `records_type_title_url_idx` ON `records` (`type`,`title`,`url`);
