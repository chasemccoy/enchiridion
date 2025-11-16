-- Create FTS5 virtual table for full-text search on records
CREATE VIRTUAL TABLE IF NOT EXISTS records_fts USING fts5(
  id UNINDEXED,
  title,
  summary,
  content,
  notes,
  tokenize='unicode61'
);

-- Populate FTS5 table with existing records
INSERT INTO records_fts(id, title, summary, content, notes)
SELECT id, title, summary, content, notes
FROM records;

-- Trigger to sync FTS5 when a new record is inserted
CREATE TRIGGER IF NOT EXISTS records_fts_insert AFTER INSERT ON records
BEGIN
  INSERT INTO records_fts(id, title, summary, content, notes)
  VALUES (NEW.id, NEW.title, NEW.summary, NEW.content, NEW.notes);
END;

-- Trigger to sync FTS5 when a record is updated
CREATE TRIGGER IF NOT EXISTS records_fts_update AFTER UPDATE ON records
WHEN (OLD.title IS NOT NEW.title) OR (OLD.summary IS NOT NEW.summary) OR (OLD.content IS NOT NEW.content) OR (OLD.notes IS NOT NEW.notes)
BEGIN
  UPDATE records_fts
  SET title = NEW.title, summary = NEW.summary, content = NEW.content, notes = NEW.notes
  WHERE id = NEW.id;
END;

-- Trigger to sync FTS5 when a record is deleted
CREATE TRIGGER IF NOT EXISTS records_fts_delete AFTER DELETE ON records
BEGIN
  DELETE FROM records_fts WHERE id = OLD.id;
END;

