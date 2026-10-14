import { PoolClient } from 'pg';
import { getPool } from '../db/pool';
import { normalizeWhatsAppPhone } from '../utils/phone';

export interface ProductionUsageEntry {
  phone: string;
  timestamp: number;
  campaignId: string;
}

export interface ReservationResult {
  allowed: boolean;
  currentCount: number;
  attemptedCount: number;
  limit: number;
  reason?: string;
}

export class ProductionUsageStore {
  /**
   * Returns the count of distinct recipient phone numbers contacted in the rolling 24 hours.
   */
  public async getUniqueRecipientsCountLast24Hours(windowMs: number = 24 * 60 * 60 * 1000): Promise<number> {
    const pool = getPool();
    const intervalSec = Math.floor(windowMs / 1000);
    const res = await pool.query<{ count: string }>(
      `SELECT COUNT(DISTINCT normalized_phone) AS count
       FROM recipient_reservations
       WHERE reserved_at >= NOW() - ($1 || ' seconds')::interval;`,
      [intervalSec]
    );
    return parseInt(res.rows[0]?.count || '0', 10);
  }

  /**
   * Returns list of unique phones in the rolling 24-hour window.
   */
  public async getUniquePhonesLast24Hours(windowMs: number = 24 * 60 * 60 * 1000): Promise<string[]> {
    const pool = getPool();
    const intervalSec = Math.floor(windowMs / 1000);
    const res = await pool.query<{ normalized_phone: string }>(
      `SELECT DISTINCT normalized_phone
       FROM recipient_reservations
       WHERE reserved_at >= NOW() - ($1 || ' seconds')::interval;`,
      [intervalSec]
    );
    return res.rows.map((r) => r.normalized_phone);
  }

  /**
   * Atomic reservation check for concurrent campaigns.
   * Ensures multiple concurrent campaigns cannot bypass the rolling 24-hour limit.
   * If a client is provided, participates in caller's active database transaction.
   * Otherwise, checks out a client from the pool and runs within its own transaction.
   */
  public async checkAndReserveRecipients(params: {
    campaignId: string;
    phones: string[];
    limit: number;
    windowMs?: number;
    client?: PoolClient;
  }): Promise<ReservationResult> {
    const { campaignId, phones, limit, windowMs = 24 * 60 * 60 * 1000, client: externalClient } = params;
    const intervalSec = Math.floor(windowMs / 1000);

    const pool = getPool();
    const client = externalClient || (await pool.connect());
    const isInternalTransaction = !externalClient;

    try {
      if (isInternalTransaction) {
        await client.query('BEGIN;');
      }

      // 1. Ensure mutex lock row exists and acquire exclusive transaction lock
      await client.query(`
        INSERT INTO app_locks (lock_key, description, locked_at)
        VALUES ('production_quota_reservation', 'Serializes 24h rolling quota check', NOW())
        ON CONFLICT (lock_key) DO UPDATE SET locked_at = NOW();
      `);

      await client.query(`
        SELECT lock_key FROM app_locks
        WHERE lock_key = 'production_quota_reservation'
        FOR UPDATE;
      `);

      // 2. Normalize requested phone numbers
      const normalizedIncoming = Array.from(
        new Set(
          phones
            .map((p) => normalizeWhatsAppPhone(p))
            .filter((p): p is string => !!p)
        )
      );

      // 3. Count distinct recipients currently in the rolling window
      const countRes = await client.query<{ current_unique: string }>(
        `SELECT COUNT(DISTINCT normalized_phone) AS current_unique
         FROM recipient_reservations
         WHERE reserved_at >= NOW() - ($1 || ' seconds')::interval;`,
        [intervalSec]
      );
      const currentCount = parseInt(countRes.rows[0]?.current_unique || '0', 10);

      // 4. Calculate how many NEW unique recipients this batch will add
      const newRecipientsRes = await client.query<{ new_unique_count: string }>(
        `WITH incoming_list AS (
           SELECT DISTINCT t.phone
           FROM unnest($1::text[]) AS t(phone)
         ),
         active_recipients AS (
           SELECT DISTINCT r.normalized_phone AS phone
           FROM recipient_reservations r
           WHERE r.reserved_at >= NOW() - ($2 || ' seconds')::interval
         )
         SELECT COUNT(*)::text AS new_unique_count
         FROM incoming_list i
         WHERE i.phone NOT IN (SELECT a.phone FROM active_recipients a);`,
        [normalizedIncoming, intervalSec]
      );
      const attemptedNewCount = parseInt(newRecipientsRes.rows[0]?.new_unique_count || '0', 10);
      const projectedCount = currentCount + attemptedNewCount;

      if (projectedCount > limit) {
        if (isInternalTransaction) {
          await client.query('ROLLBACK;');
        }
        const excess = projectedCount - limit;
        return {
          allowed: false,
          currentCount,
          attemptedCount: normalizedIncoming.length,
          limit,
          reason: `Rolling 24-hour recipient limit reached (${projectedCount}/${limit} unique numbers). Limit would be exceeded by ${excess}.`,
        };
      }

      // 5. Allowed: record recipient reservations
      if (normalizedIncoming.length > 0) {
        await client.query(
          `INSERT INTO campaigns (campaign_id, campaign_name, mode, status, template_name)
           VALUES ($1, 'Quota Reservation Campaign', 'production', 'processing', 'default')
           ON CONFLICT (campaign_id) DO NOTHING;`,
          [campaignId]
        );

        await client.query(
          `INSERT INTO recipient_reservations (campaign_id, normalized_phone, reserved_at)
           SELECT $1, t.phone, NOW()
           FROM unnest($2::text[]) AS t(phone)
           ON CONFLICT (campaign_id, normalized_phone) DO NOTHING;`,
          [campaignId, normalizedIncoming]
        );
      }

      if (isInternalTransaction) {
        await client.query('COMMIT;');
      }

      return {
        allowed: true,
        currentCount: projectedCount,
        attemptedCount: normalizedIncoming.length,
        limit,
      };
    } catch (err: any) {
      if (isInternalTransaction) {
        await client.query('ROLLBACK;').catch(() => {});
      }
      return {
        allowed: false,
        currentCount: 0,
        attemptedCount: phones.length,
        limit,
        reason: `Error during quota reservation: ${err.message}`,
      };
    } finally {
      if (isInternalTransaction) {
        client.release();
      }
    }
  }

  /**
   * Clears usage history (used strictly for test suites).
   */
  public async clear(): Promise<void> {
    const pool = getPool();
    await pool.query('DELETE FROM recipient_reservations;');
  }
}

export const productionUsageStore = new ProductionUsageStore();
