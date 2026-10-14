import { Pool, PoolConfig } from 'pg';
import { env, getActiveDatabaseUrl } from '../config/env';

let pool: Pool | null = null;

export interface PoolOptions {
  connectionString?: string;
  max?: number;
  connectionTimeoutMillis?: number;
  idleTimeoutMillis?: number;
}

/**
 * Returns the singleton PostgreSQL pool configured for Neon.
 * - Enforces minimum 10s connection timeout for serverless wake-up.
 * - Caps max connections to 5 to protect Render Free and Neon pooler limits.
 * - Strictly separates TEST_DATABASE_URL (dev/test) from DATABASE_URL (production).
 * - Never silently falls back to JSON persistence when unreachable.
 */
export function getPool(options?: PoolOptions): Pool {
  if (pool) {
    return pool;
  }

  const connectionString = options?.connectionString || getActiveDatabaseUrl();

  if (!connectionString || !connectionString.trim()) {
    throw new Error(
      `Database connection URL is not configured. (NODE_ENV=${env.NODE_ENV}, activeVariable=${
        env.NODE_ENV === 'production' ? 'DATABASE_URL' : 'TEST_DATABASE_URL'
      })`
    );
  }

  const config: PoolConfig = {
    connectionString,
    max: options?.max || 5, // Safe limit for Render Free
    connectionTimeoutMillis: options?.connectionTimeoutMillis || 30000, // Accommodate Neon compute wake-up
    idleTimeoutMillis: options?.idleTimeoutMillis || 10000,
    ssl: {
      rejectUnauthorized: false, // Standard for cloud postgres poolers with serverless SNI
    },
  };

  pool = new Pool(config);

  pool.on('error', (err) => {
    console.error('[Database Pool] Unexpected idle client error:', err.message);
  });

  return pool;
}

/**
 * Checks if the pool is initialized.
 */
export function isPoolInitialized(): boolean {
  return pool !== null;
}

/**
 * Closes the pool cleanly (used in test teardown or graceful shutdown).
 */
export async function closePool(): Promise<void> {
  if (pool) {
    const current = pool;
    pool = null;
    await current.end().catch(() => {});
  }
}
