import fs from 'fs';
import path from 'path';
import { Pool, PoolClient } from 'pg';
import { getPool } from './pool';

export interface MigrationResult {
  success: boolean;
  applied: string[];
  skipped: string[];
  total: number;
  durationMs: number;
  error?: string;
}

/**
 * Resolves the absolute path to the migrations directory across both
 * development (tsx / ts) and production (compiled dist / js).
 */
export function getMigrationsDir(): string {
  const candidates = [
    path.join(__dirname, 'migrations'),
    path.join(__dirname, '../db/migrations'),
    path.resolve(__dirname, '../../src/db/migrations'),
    path.resolve(__dirname, '../../../src/db/migrations'),
    path.join(process.cwd(), 'src/db/migrations'),
    path.join(process.cwd(), 'dist/src/db/migrations'),
    path.join(process.cwd(), 'backend/src/db/migrations'),
    path.join(process.cwd(), 'backend/dist/src/db/migrations'),
  ];

  for (const c of candidates) {
    if (fs.existsSync(c)) {
      return c;
    }
  }

  throw new Error(`Migrations directory not found in candidate locations: ${candidates.join(', ')}`);
}

/**
 * Safely sets the transaction-local PostgreSQL session variable for migration 012.
 * Uses the same PoolClient and transaction.
 *
 * Requirements:
 * 1. Supports an explicit migration-only owner configuration (INITIAL_BUSINESS_OWNER_EMAIL).
 * 2. Uses PostgreSQL set_config('glowblast.initial_owner_email', $1, true).
 * 3. Validates that the selected email belongs to an existing verified user in the database.
 * 4. Never prints the email or sensitive account information to logs or error messages.
 * 5. If ownership is ambiguous and no valid owner has been explicitly supplied, aborts migration 012 safely.
 */
export async function prepareMigration012(
  client: PoolClient,
  overrideOwnerEmail?: string
): Promise<void> {
  const configuredEmail = (overrideOwnerEmail || process.env.INITIAL_BUSINESS_OWNER_EMAIL)?.trim();

  if (configuredEmail) {
    // Validate that the selected email belongs to an existing verified user
    const userRes = await client.query<{ id: string; email_verified: boolean }>(
      'SELECT id, email_verified FROM users WHERE LOWER(email) = LOWER($1);',
      [configuredEmail]
    );

    if (userRes.rows.length === 0) {
      throw new Error(
        'Configured INITIAL_BUSINESS_OWNER_EMAIL does not match any existing registered user.'
      );
    }

    if (!userRes.rows[0].email_verified) {
      throw new Error(
        'Configured INITIAL_BUSINESS_OWNER_EMAIL does not belong to a verified user account.'
      );
    }

    // Bind session variable safely for this transaction only (is_local = true)
    await client.query(
      `SELECT set_config('glowblast.initial_owner_email', $1, true);`,
      [configuredEmail]
    );
    console.log('[Migrator] Initial business owner confirmed and bound to migration 012 transaction.');
  } else {
    // If not supplied, verify whether ownership is ambiguous
    const verifiedUsersRes = await client.query<{ count: string }>(
      'SELECT COUNT(*) as count FROM users WHERE email_verified = true;'
    );
    const totalUsersRes = await client.query<{ count: string }>(
      'SELECT COUNT(*) as count FROM users;'
    );

    const verifiedCount = parseInt(verifiedUsersRes.rows[0]?.count || '0', 10);
    const totalCount = parseInt(totalUsersRes.rows[0]?.count || '0', 10);

    if (verifiedCount > 1 || (verifiedCount === 0 && totalCount > 1)) {
      throw new Error(
        `Ambiguous initial business ownership: Found ${verifiedCount} verified users and ${totalCount} total users. Set INITIAL_BUSINESS_OWNER_EMAIL before running migration 012.`
      );
    }
  }
}

/**
 * Runs all pending migrations idempotently against the database.
 * Tracks applied migrations in `schema_migrations`.
 */
export async function runMigrations(
  customPool?: Pool,
  options?: { initialOwnerEmail?: string }
): Promise<MigrationResult> {
  const pool = customPool || getPool();
  const client: PoolClient = await pool.connect();
  const startTime = Date.now();

  const applied: string[] = [];
  const skipped: string[] = [];

  try {
    const migrationsDir = getMigrationsDir();
    const files = fs
      .readdirSync(migrationsDir)
      .filter((f) => f.endsWith('.sql'))
      .sort();

    // 1. Ensure schema_migrations table exists
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version VARCHAR(64) PRIMARY KEY,
        description TEXT NOT NULL,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);

    // 2. Fetch already applied versions
    const appliedRows = await client.query<{ version: string }>(
      'SELECT version FROM schema_migrations;'
    );
    const appliedSet = new Set(appliedRows.rows.map((r) => r.version));

    // 3. Apply pending migrations sequentially
    for (const file of files) {
      const version = path.basename(file, '.sql');

      if (appliedSet.has(version)) {
        skipped.push(version);
        continue;
      }

      console.log(`[Migrator] Applying migration: ${file}...`);
      const filePath = path.join(migrationsDir, file);
      const sql = fs.readFileSync(filePath, 'utf8');

      await client.query('BEGIN;');
      try {
        if (version === '012_backfill_business_ids' || version.startsWith('012_')) {
          await prepareMigration012(client, options?.initialOwnerEmail);
        }

        await client.query(sql);
        await client.query(
          `INSERT INTO schema_migrations (version, description, applied_at)
           VALUES ($1, $2, NOW());`,
          [version, file]
        );
        await client.query('COMMIT;');
        applied.push(version);
        console.log(`[Migrator] Successfully applied: ${file}`);
      } catch (err: any) {
        await client.query('ROLLBACK;');
        console.error(`[Migrator] Migration ${file} failed:`, err.message);
        return {
          success: false,
          applied,
          skipped,
          total: files.length,
          durationMs: Date.now() - startTime,
          error: `Migration ${file} failed: ${err.message}`,
        };
      }
    }

    return {
      success: true,
      applied,
      skipped,
      total: files.length,
      durationMs: Date.now() - startTime,
    };
  } finally {
    client.release();
  }
}

// Allow CLI execution via `tsx src/db/migrator.ts` or `node dist/src/db/migrator.js`
if (require.main === module) {
  runMigrations()
    .then((res) => {
      console.log('Migration run result:', res);
      process.exit(res.success ? 0 : 1);
    })
    .catch((err) => {
      console.error('Fatal migration error:', err);
      process.exit(1);
    });
}
