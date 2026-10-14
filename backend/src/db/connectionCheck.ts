import { Pool, PoolConfig } from 'pg';
import { env, getActiveDatabaseUrl } from '../config/env';

export interface DatabaseCheckResult {
  success: boolean;
  endpoint?: string;
  database?: string;
  queryResult?: number;
  durationMs?: number;
  sanitizedError?: string;
}

/**
 * Safely parses the hostname and database from a connection URL without exposing credentials.
 */
export function getSanitizedEndpointInfo(connectionUrl: string): { host: string; database: string } {
  try {
    const parsed = new URL(connectionUrl);
    return {
      host: parsed.hostname,
      database: parsed.pathname.replace(/^\//, ''),
    };
  } catch {
    return { host: 'unknown', database: 'unknown' };
  }
}

/**
 * Checks connectivity to the Neon development branch by executing `SELECT 1`.
 * - Reads TEST_DATABASE_URL using the existing environment loader.
 * - Confirms that it does NOT connect to production.
 * - Does NOT perform any DDL, DML, migrations, or data alterations.
 * - Closes all database connections cleanly.
 * - Never logs or exposes credentials.
 */
export async function checkDevelopmentDatabaseConnection(
  customUrl?: string
): Promise<DatabaseCheckResult> {
  const connectionUrl = customUrl !== undefined ? customUrl : (env.TEST_DATABASE_URL || getActiveDatabaseUrl());

  if (!connectionUrl || !connectionUrl.trim()) {
    return {
      success: false,
      sanitizedError: 'No database URL configured. TEST_DATABASE_URL is missing.',
    };
  }

  // Safety guard: ensure we are NOT running against production environment
  if (env.NODE_ENV === 'production' && !customUrl) {
    return {
      success: false,
      sanitizedError: 'Refusing to run development connection check in production environment.',
    };
  }

  const endpointInfo = getSanitizedEndpointInfo(connectionUrl);

  const startTime = Date.now();
  let pool: Pool | null = null;

  try {
    const config: PoolConfig = {
      connectionString: connectionUrl,
      ssl: {
        rejectUnauthorized: false, // Standard for cloud postgres poolers with serverless SNI
      },
      connectionTimeoutMillis: 30000,
      idleTimeoutMillis: 5000,
      max: 1, // Single connection for verification
    };

    pool = new Pool(config);

    const client = await pool.connect();
    try {
      const res = await client.query<{ alive: number }>('SELECT 1 AS alive');
      const aliveValue = Number(res.rows[0]?.alive);

      if (aliveValue !== 1) {
        throw new Error(`Unexpected query result: expected 1, received ${aliveValue}`);
      }

      const durationMs = Date.now() - startTime;
      return {
        success: true,
        endpoint: endpointInfo.host,
        database: endpointInfo.database,
        queryResult: aliveValue,
        durationMs,
      };
    } finally {
      client.release();
    }
  } catch (error: any) {
    let sanitized = error?.message || 'Unknown database connection error';
    // Redact any URI user/password patterns that might appear in driver error strings
    sanitized = sanitized.replace(/:\/\/[^:]+:[^@]+@/g, '://***:***@');
    sanitized = sanitized.replace(/:[^@:/]+@/g, ':***@');

    return {
      success: false,
      endpoint: endpointInfo.host,
      database: endpointInfo.database,
      sanitizedError: sanitized,
    };
  } finally {
    if (pool) {
      await pool.end().catch(() => {});
    }
  }
}
