/* eslint-disable no-console */

/**
 * SQLite Database Backup/Restore Module
 *
 * Based on sqlite-diffable by Simon Willison
 * Provides functionality to backup SQLite databases to JSON files
 * and restore them back to SQLite format.
 */

import Database from 'better-sqlite3';
import { promises as fs, readFileSync } from 'fs';
import path from 'path';

// Constants
const METADATA_FILE_SUFFIX = '.metadata.json';
const DATA_FILE_SUFFIX = '.ndjson';
const BACKUP_MANIFEST_FILENAME = 'backup_manifest.json';
const DATABASE_METADATA_FILENAME = 'database_metadata.json';
const INDEXES_SCHEMA_FILENAME = 'indexes.sql';
const VIEWS_SCHEMA_FILENAME = 'views.sql';
const TRIGGERS_SCHEMA_FILENAME = 'triggers.sql';

export interface TableMetadata {
  name: string;
  columns: string[];
  schema: string;
  rowCount?: number;
}

export interface BackupOptions {
  outputDir: string;
  tables?: string[];
  excludeTables?: string[];
  includePragma?: boolean;
  includeSchema?: boolean;
}

export interface RestoreOptions {
  inputDir: string;
  tables?: string[];
  replace?: boolean;
  createTables?: boolean;
  restoreSchema?: boolean;
}

export interface BackupResult {
  tables: string[];
  totalRows: number;
  outputDir: string;
  timestamp: string;
}

export interface RestoreResult {
  tables: string[];
  totalRows: number;
  created: string[];
  updated: string[];
}

export class SQLiteDiffable {
  private db: Database.Database;

  constructor(databasePath: string) {
    this.db = new Database(databasePath);
  }

  /**
   * Backup database to JSON files
   */
  async backup(options: BackupOptions): Promise<BackupResult> {
    const {
      outputDir,
      tables,
      excludeTables = [],
      includePragma = false,
      includeSchema = true,
    } = options;

    // Ensure output directory exists
    await fs.mkdir(outputDir, { recursive: true });

    // Get list of tables to backup
    const tablesToBackup = this.getTableList(tables, excludeTables);

    let totalRows = 0;
    const backedUpTables: string[] = [];

    for (const tableName of tablesToBackup) {
      try {
        const rowCount = await this.backupTable(tableName, outputDir);
        totalRows += rowCount;
        backedUpTables.push(tableName);
        console.log(`Backed up table '${tableName}': ${rowCount} rows`);
      } catch (error) {
        console.error(`Failed to backup table '${tableName}':`, error);
        throw error;
      }
    }

    // Save database metadata
    if (includePragma) {
      await this.saveDatabaseMetadata(outputDir);
    }

    // Save schema objects (indexes, views, triggers)
    if (includeSchema) {
      await this.saveSchemaObjects(outputDir);
    }

    // Create backup manifest
    const manifest = {
      timestamp: new Date().toISOString(),
      database_path: this.db.name,
      tables: backedUpTables,
      total_rows: totalRows,
      pragma_info_included: includePragma,
      schema_objects_included: includeSchema,
    };

    await fs.writeFile(
      path.join(outputDir, BACKUP_MANIFEST_FILENAME),
      JSON.stringify(manifest, null, 2),
    );

    return {
      tables: backedUpTables,
      totalRows,
      outputDir,
      timestamp: manifest.timestamp,
    };
  }

  /**
   * Restore database from JSON files
   */
  async restore(options: RestoreOptions): Promise<RestoreResult> {
    const {
      inputDir,
      tables,
      replace = false,
      createTables = true,
      restoreSchema = true,
    } = options;

    // Validate backup directory exists
    try {
      await fs.access(inputDir);
    } catch {
      throw new Error(`Backup directory '${inputDir}' does not exist or is not accessible`);
    }

    // Read backup manifest
    const manifestPath = path.join(inputDir, BACKUP_MANIFEST_FILENAME);
    let availableTables: string[] = [];

    try {
      const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf-8'));
      availableTables = manifest.tables || [];
    } catch {
      // If no manifest, scan for metadata files
      try {
        const files = await fs.readdir(inputDir);
        availableTables = files
          .filter((file) => file.endsWith(METADATA_FILE_SUFFIX))
          .map((file) => file.replace(METADATA_FILE_SUFFIX, ''));
      } catch (error) {
        throw new Error(`Failed to read backup directory '${inputDir}'`, { cause: error });
      }
    }

    // Validate that we have at least some tables to restore
    if (availableTables.length === 0) {
      throw new Error(`No valid backup files found in '${inputDir}'`);
    }

    // Determine which tables to restore
    const tablesToRestore = tables || availableTables;

    let totalRows = 0;
    const restoredTables: string[] = [];
    const createdTables: string[] = [];
    const updatedTables: string[] = [];

    // Begin transaction for all restore operations
    const transaction = this.db.transaction(() => {
      for (const tableName of tablesToRestore) {
        if (!availableTables.includes(tableName)) {
          console.warn(`Table '${tableName}' not found in backup, skipping`);
          continue;
        }

        const result = this.restoreTable(tableName, inputDir, { replace, createTables });
        totalRows += result.rowCount;
        restoredTables.push(tableName);

        if (result.created) {
          createdTables.push(tableName);
        } else {
          updatedTables.push(tableName);
        }

        console.log(`Restored table '${tableName}': ${result.rowCount} rows`);
      }
    });

    try {
      transaction();
    } catch (error) {
      console.error('Restore transaction failed, all changes rolled back:', error);
      throw error;
    }

    // Restore schema objects (indexes, views, triggers) after data
    if (restoreSchema) {
      await this.restoreSchemaObjects(inputDir);
    }

    return {
      tables: restoredTables,
      totalRows,
      created: createdTables,
      updated: updatedTables,
    };
  }

  /**
   * Backup a single table to JSON files
   */
  private async backupTable(tableName: string, outputDir: string): Promise<number> {
    // Get table metadata
    const metadata = this.getTableMetadata(tableName);

    // Write metadata file
    const metadataPath = path.join(outputDir, `${tableName}${METADATA_FILE_SUFFIX}`);
    await fs.writeFile(metadataPath, JSON.stringify(metadata, null, 2));

    // Export table data to NDJSON
    const dataPath = path.join(outputDir, `${tableName}${DATA_FILE_SUFFIX}`);
    const stmt = this.db.prepare(`SELECT * FROM \`${tableName}\``);

    const writeStream = await fs.open(dataPath, 'w');
    let rowCount = 0;

    try {
      for (const row of stmt.iterate()) {
        // Convert row to array of values, maintaining column order
        const rowArray = metadata.columns.map((colName) =>
          this.serializeValue((row as Record<string, unknown>)[colName]),
        );
        await writeStream.write(JSON.stringify(rowArray) + '\n');
        rowCount++;
      }
    } finally {
      await writeStream.close();
    }

    // Update metadata with row count
    metadata.rowCount = rowCount;
    await fs.writeFile(metadataPath, JSON.stringify(metadata, null, 2));

    return rowCount;
  }

  /**
   * Restore a single table from JSON files
   */
  private restoreTable(
    tableName: string,
    inputDir: string,
    options: { replace: boolean; createTables: boolean },
  ): { rowCount: number; created: boolean } {
    const { replace, createTables } = options;

    // Read metadata
    const metadataPath = path.join(inputDir, `${tableName}${METADATA_FILE_SUFFIX}`);
    const metadata: TableMetadata = JSON.parse(readFileSync(metadataPath, 'utf-8'));

    // Check if table exists
    const tableExists = this.tableExists(tableName);
    let created = false;

    if (tableExists && !replace) {
      throw new Error(`Table '${tableName}' already exists. Use replace option to overwrite.`);
    }

    if (tableExists && replace) {
      // Drop existing table
      this.db.exec(`DROP TABLE IF EXISTS \`${tableName}\``);
    }

    if (!tableExists || replace) {
      if (createTables) {
        // Create table using original schema
        this.db.exec(metadata.schema);
        created = true;
      } else {
        throw new Error(`Table '${tableName}' does not exist and createTables is false`);
      }
    }

    // Read and insert data
    const dataPath = path.join(inputDir, `${tableName}${DATA_FILE_SUFFIX}`);
    const dataContent = readFileSync(dataPath, 'utf-8');
    const lines = dataContent
      .trim()
      .split('\n')
      .filter((line) => line.length > 0);

    if (lines.length === 0) {
      return { rowCount: 0, created };
    }

    // Prepare insert statement
    const columns = metadata.columns;
    const placeholders = columns.map(() => '?').join(', ');
    const insertStmt = this.db.prepare(
      `INSERT INTO \`${tableName}\` (\`${columns.join('`, `')}\`) VALUES (${placeholders})`,
    );

    let rowCount = 0;
    for (const line of lines) {
      const rowArray = JSON.parse(line) as unknown[];
      // Row is now an array of values in column order
      const values = rowArray.map((value) => this.deserializeValue(value));
      insertStmt.run(values);
      rowCount++;
    }

    return { rowCount, created };
  }

  /**
   * Get metadata for a table
   */
  private getTableMetadata(tableName: string): TableMetadata {
    // Get table schema
    const schemaStmt = this.db.prepare(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
    );
    const schemaResult = schemaStmt.get(tableName) as { sql: string } | undefined;

    if (!schemaResult) {
      throw new Error(`Table '${tableName}' not found`);
    }

    // Get column names
    const columnsStmt = this.db.prepare(`PRAGMA table_info(\`${tableName}\`)`);
    const columns = columnsStmt.all() as Array<{ name: string }>;

    return {
      name: tableName,
      columns: columns.map((col) => col.name),
      schema: schemaResult.sql,
    };
  }

  /**
   * Get list of tables to backup
   */
  private getTableList(includeTables?: string[], excludeTables: string[] = []): string[] {
    const rows = this.db
      .prepare(
        "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      )
      .all() as Array<{ name: string; sql: string | null }>;

    // Skip virtual tables and their backing/companion tables. sqlite-vec's
    // `vec_records` is a vec0 virtual table whose rows can't be dumped without
    // the loaded extension (a plain backup connection throws "no such module:
    // vec0"), and its shadow tables (`vec_records_*`, including the regenerable
    // `vec_records_meta` hash cache) are internal state rebuilt by `pnpm embed`.
    // Detect them generically so the backup never trips over one.
    const virtualTableNames = rows
      .filter((t) => /^\s*CREATE\s+VIRTUAL\s+TABLE/i.test(t.sql ?? ''))
      .map((t) => t.name);
    const isVirtualOrShadow = (name: string) =>
      virtualTableNames.some((v) => name === v || name.startsWith(`${v}_`));

    const tableNames = rows.map((t) => t.name).filter((name) => !isVirtualOrShadow(name));

    if (includeTables) {
      return includeTables.filter(
        (name) => tableNames.includes(name) && !excludeTables.includes(name),
      );
    }

    return tableNames.filter((name) => !excludeTables.includes(name));
  }

  /**
   * Check if table exists
   */
  private tableExists(tableName: string): boolean {
    const stmt = this.db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name=?");
    return !!stmt.get(tableName);
  }

  /**
   * Serialize a single value for JSON export
   */
  private serializeValue(value: unknown): unknown {
    if (value === null) {
      return null;
    } else if (Buffer.isBuffer(value)) {
      // Handle BLOB data
      return {
        __type: 'blob',
        __value: value.toString('base64'),
      };
    } else if (value instanceof Date) {
      return {
        __type: 'date',
        __value: value.toISOString(),
      };
    } else if (typeof value === 'bigint') {
      return {
        __type: 'bigint',
        __value: value.toString(),
      };
    } else {
      return value;
    }
  }

  /**
   * Deserialize a value from JSON import
   */
  private deserializeValue(value: unknown): unknown {
    if (value === null || value === undefined) {
      return null;
    }

    if (typeof value === 'object' && value !== null && '__type' in value) {
      const typedValue = value as Record<string, unknown>;
      switch (typedValue.__type) {
        case 'blob':
          return Buffer.from(typedValue.__value as string, 'base64');
        case 'date':
          return new Date(typedValue.__value as string);
        case 'bigint':
          return BigInt(typedValue.__value as string);
        default:
          return typedValue.__value;
      }
    }

    return value;
  }

  /**
   * Save schema objects (indexes, views, triggers) to separate SQL files
   */
  private async saveSchemaObjects(outputDir: string): Promise<void> {
    const schemaStmt = this.db.prepare(`
      SELECT type, name, sql
      FROM sqlite_master
      WHERE type IN ('index', 'view', 'trigger')
      AND name NOT LIKE 'sqlite_%'
      AND name NOT LIKE 'vec_%'
      AND sql IS NOT NULL
      ORDER BY type, name
    `);

    const schemaObjects = schemaStmt.all() as Array<{
      type: string;
      name: string;
      sql: string;
    }>;

    // Group by type
    const indexes = schemaObjects.filter((obj) => obj.type === 'index');
    const views = schemaObjects.filter((obj) => obj.type === 'view');
    const triggers = schemaObjects.filter((obj) => obj.type === 'trigger');

    // Save indexes
    if (indexes.length > 0) {
      const indexSql = indexes.map((idx) => `-- Index: ${idx.name}\n${idx.sql};`).join('\n\n');

      await fs.writeFile(path.join(outputDir, INDEXES_SCHEMA_FILENAME), `${indexSql}\n`);
    }

    // Save views
    if (views.length > 0) {
      const viewSql = views.map((view) => `-- View: ${view.name}\n${view.sql};`).join('\n\n');

      await fs.writeFile(
        path.join(outputDir, VIEWS_SCHEMA_FILENAME),
        `-- SQLite Views Backup\n-- Generated: ${new Date().toISOString()}\n\n${viewSql}\n`,
      );
    }

    // Save triggers
    if (triggers.length > 0) {
      const triggerSql = triggers
        .map((trigger) => `-- Trigger: ${trigger.name}\n${trigger.sql};`)
        .join('\n\n');

      await fs.writeFile(
        path.join(outputDir, TRIGGERS_SCHEMA_FILENAME),
        `-- SQLite Triggers Backup\n-- Generated: ${new Date().toISOString()}\n\n${triggerSql}\n`,
      );
    }

    console.log(
      `Schema objects backed up: ${indexes.length} indexes, ${views.length} views, ${triggers.length} triggers`,
    );
  }

  /**
   * Restore schema objects from SQL files
   */
  private async restoreSchemaObjects(inputDir: string): Promise<void> {
    const schemaFiles = [
      { file: INDEXES_SCHEMA_FILENAME, type: 'indexes' },
      { file: VIEWS_SCHEMA_FILENAME, type: 'views' },
      { file: TRIGGERS_SCHEMA_FILENAME, type: 'triggers' },
    ];

    for (const { file, type } of schemaFiles) {
      const filePath = path.join(inputDir, file);

      try {
        await fs.access(filePath);
        const sqlContent = await fs.readFile(filePath, 'utf-8');

        // Split by statements and execute each one
        const statements = sqlContent
          .split(';')
          .map((stmt) => stmt.trim())
          .filter((stmt) => stmt.length > 0 && !stmt.startsWith('--'));

        let executedCount = 0;
        for (const statement of statements) {
          try {
            this.db.exec(statement + ';');
            executedCount++;
          } catch (error) {
            console.warn(`Failed to execute ${type} statement: ${error}`);
            // Continue with other statements rather than failing completely
          }
        }

        if (executedCount > 0) {
          console.log(`Restored ${executedCount} ${type}`);
        }
      } catch {
        // File doesn't exist, which is fine - not all backups will have all schema types
        continue;
      }
    }
  }

  /**
   * Save database-level metadata
   */
  private async saveDatabaseMetadata(outputDir: string): Promise<void> {
    const pragmas = [
      'application_id',
      'auto_vacuum',
      'cache_size',
      'case_sensitive_like',
      'cell_size_check',
      'checkpoint_fullfsync',
      'collation_list',
      'compile_options',
      'database_list',
      'encoding',
      'foreign_key_check',
      'foreign_key_list',
      'foreign_keys',
      'freelist_count',
      'fullfsync',
      'integrity_check',
      'journal_mode',
      'journal_size_limit',
      'locking_mode',
      'max_page_count',
      'page_count',
      'page_size',
      'parser_trace',
      'query_only',
      'quick_check',
      'read_uncommitted',
      'recursive_triggers',
      'reverse_unordered_selects',
      'schema_version',
      'secure_delete',
      'synchronous',
      'table_list',
      'temp_store',
      'threads',
      'user_version',
      'wal_autocheckpoint',
      'wal_checkpoint',
      'writable_schema',
    ];

    const metadata: Record<string, unknown> = {};

    for (const pragma of pragmas) {
      try {
        const result = this.db.pragma(pragma);
        metadata[pragma] = result;
      } catch {
        // Some pragmas might not be available, skip them
        continue;
      }
    }

    await fs.writeFile(
      path.join(outputDir, DATABASE_METADATA_FILENAME),
      JSON.stringify(metadata, null, 2),
    );
  }

  /**
   * Compare two backup directories to show differences
   */
  async diff(
    dir1: string,
    dir2: string,
  ): Promise<{
    added: string[];
    removed: string[];
    modified: string[];
    unchanged: string[];
  }> {
    return compareBackups(dir1, dir2);
  }

  /**
   * Get backup statistics
   */
  async getBackupStats(backupDir: string): Promise<{
    tables: number;
    totalRows: number;
    totalSize: number;
    timestamp?: string;
  }> {
    let totalRows = 0;
    let totalSize = 0;
    let tableCount = 0;
    let timestamp: string | undefined;

    try {
      // Read manifest if available
      const manifestPath = path.join(backupDir, BACKUP_MANIFEST_FILENAME);
      const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf-8'));
      timestamp = manifest.timestamp;
      totalRows = manifest.total_rows || 0;
      tableCount = manifest.tables?.length || 0;
    } catch {
      // Fallback: scan metadata files
      const files = await fs.readdir(backupDir);
      const metadataFiles = files.filter((file) => file.endsWith(METADATA_FILE_SUFFIX));

      for (const file of metadataFiles) {
        try {
          const metadata: TableMetadata = JSON.parse(
            await fs.readFile(path.join(backupDir, file), 'utf-8'),
          );
          totalRows += metadata.rowCount || 0;
          tableCount++;
        } catch {
          continue;
        }
      }
    }

    // Calculate total size
    try {
      const files = await fs.readdir(backupDir);
      for (const file of files) {
        const stats = await fs.stat(path.join(backupDir, file));
        totalSize += stats.size;
      }
    } catch {
      totalSize = 0;
    }

    return {
      tables: tableCount,
      totalRows,
      totalSize,
      timestamp,
    };
  }

  /**
   * Close the database connection
   */
  close(): void {
    this.db.close();
  }
}

/**
 * Convenience function to create a backup
 */
export async function createBackup(
  databasePath: string,
  outputDir: string,
  options: Partial<BackupOptions> = {},
): Promise<BackupResult> {
  const diffable = new SQLiteDiffable(databasePath);

  try {
    return await diffable.backup({ outputDir, ...options });
  } finally {
    diffable.close();
  }
}

/**
 * Convenience function to restore from backup
 */
export async function restoreBackup(
  databasePath: string,
  inputDir: string,
  options: Partial<RestoreOptions> = {},
): Promise<RestoreResult> {
  const diffable = new SQLiteDiffable(databasePath);

  try {
    return await diffable.restore({ inputDir, ...options });
  } finally {
    diffable.close();
  }
}

/**
 * Convenience function to compare two backups
 */
export async function compareBackups(
  dir1: string,
  dir2: string,
): Promise<{
  added: string[];
  removed: string[];
  modified: string[];
  unchanged: string[];
}> {
  const getTables = async (dir: string): Promise<Set<string>> => {
    try {
      const files = await fs.readdir(dir);
      return new Set(
        files
          .filter((file) => file.endsWith(METADATA_FILE_SUFFIX))
          .map((file) => file.replace(METADATA_FILE_SUFFIX, '')),
      );
    } catch {
      return new Set();
    }
  };

  const tables1 = await getTables(dir1);
  const tables2 = await getTables(dir2);

  const added = Array.from(tables2).filter((table) => !tables1.has(table));
  const removed = Array.from(tables1).filter((table) => !tables2.has(table));
  const common = Array.from(tables1).filter((table) => tables2.has(table));

  const modified: string[] = [];
  const unchanged: string[] = [];

  for (const table of common) {
    try {
      const data1 = await fs.readFile(path.join(dir1, `${table}${DATA_FILE_SUFFIX}`), 'utf-8');
      const data2 = await fs.readFile(path.join(dir2, `${table}${DATA_FILE_SUFFIX}`), 'utf-8');

      if (data1 === data2) {
        unchanged.push(table);
      } else {
        modified.push(table);
      }
    } catch {
      // If we can't read files, consider it modified
      modified.push(table);
    }
  }

  return { added, removed, modified, unchanged };
}
