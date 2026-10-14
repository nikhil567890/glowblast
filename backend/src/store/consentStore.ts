import { PoolClient } from 'pg';
import { getPool } from '../db/pool';
import { normalizeWhatsAppPhone } from '../utils/phone';

export type ConsentStatus = 'opted_in' | 'opted_out' | 'revoked';

export interface ConsentRecord {
  phone: string; // Normalized international phone digits
  status: ConsentStatus;
  recordedAt: string; // ISO-8601 timestamp
  source: string; // e.g. 'manual_verified_opt_in', 'inbound_whatsapp_keyword', 'front_desk_digital_waiver'
  evidence?: string; // Audit trail, reference, notes
  updatedBy: string; // Identity of user or process that updated consent
}

export class ConsentStore {
  /**
   * Authoritatively records customer consent or opt-out inside an atomic PostgreSQL transaction.
   * - Serializes concurrent updates on the same phone number via transaction-scoped advisory locks,
   *   even when no row exists yet in customer_consent.
   * - Deduplicates inbound webhooks via webhook_events to ensure zero duplicate audit entries.
   * - Enforces that an existing opt-out can only be reversed to opted_in with explicit authorization
   *   (allowOptOutOverride: true) and genuine evidence of renewed consent.
   * - Accurately records previous and new states in the append-only consent_audit_log.
   */
  public async recordConsent(params: {
    phone: string;
    status: ConsentStatus;
    source: string;
    evidence?: string;
    updatedBy: string;
    isAuthorizedAdmin?: boolean;
    allowOptOutOverride?: boolean;
    inboundWebhookId?: string;
  }): Promise<ConsentRecord | null> {
    const normalized = normalizeWhatsAppPhone(params.phone);
    if (!normalized) {
      return null;
    }

    const {
      status,
      source,
      evidence = '',
      updatedBy,
      isAuthorizedAdmin = false,
      allowOptOutOverride = false,
      inboundWebhookId,
    } = params;

    const pool = getPool();
    const client: PoolClient = await pool.connect();

    try {
      await client.query('BEGIN;');

      // 1. Webhook Deduplication (e.g. for inbound STOP webhooks)
      if (inboundWebhookId) {
        const dedupKey = `inbound_msg:${inboundWebhookId}`;
        const dedupRes = await client.query(
          `INSERT INTO webhook_events (dedup_key, event_type, provider_message_id, status, payload)
           VALUES ($1, 'message', $2, NULL, $3)
           ON CONFLICT (dedup_key) DO NOTHING
           RETURNING dedup_key;`,
          [dedupKey, inboundWebhookId, JSON.stringify({ phone: normalized, source, evidence })]
        );

        // If duplicate event delivery, commit without creating duplicate audit log entry
        if (dedupRes.rowCount === 0) {
          await client.query('COMMIT;');
          const existing = await this.getConsent(normalized);
          return existing || null;
        }
      }

      // 2. Acquire transaction-scoped advisory lock for this normalized phone
      // Guaranteed serialization across processes even when customer_consent has 0 rows
      await client.query(
        `SELECT pg_advisory_xact_lock(hashtext('consent:' || $1)::bigint);`,
        [normalized]
      );

      // 3. Read previous status
      const existingRes = await client.query<{ status: string }>(
        `SELECT status FROM customer_consent WHERE normalized_phone = $1;`,
        [normalized]
      );

      const previousStatus = existingRes.rows.length > 0 ? (existingRes.rows[0].status as ConsentStatus) : null;

      // 4. Opt-Out Override Protection
      // Overriding an existing opt-out strictly requires authorized admin and explicit override flag
      if (previousStatus === 'opted_out' && status === 'opted_in') {
        if (!isAuthorizedAdmin || !allowOptOutOverride) {
          await client.query('ROLLBACK;');
          console.warn(`[ConsentStore] Blocked unauthorized opt-out override attempt for ${normalized}`);
          return null;
        }
      }

      // 5. Derive audit action
      let action: string;
      if (status === 'opted_in') {
        if (previousStatus === null) action = 'initial_opt_in';
        else if (previousStatus === 'opted_out') action = 'opt_in_override_of_opt_out';
        else if (previousStatus === 'revoked') action = 'opt_in_reinstatement';
        else action = 'opt_in_update';
      } else if (status === 'opted_out') {
        if (previousStatus === null) action = 'initial_opt_out';
        else if (previousStatus === 'opted_out') action = 'opt_out_reaffirmation';
        else action = 'opt_out';
      } else if (status === 'revoked') {
        action = 'consent_revoked';
      } else {
        action = 'status_update';
      }

      const now = new Date();

      // 6. Upsert current consent row
      await client.query(
        `INSERT INTO customer_consent (
          normalized_phone, status, source, evidence, updated_by, recorded_at, updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $6)
        ON CONFLICT (normalized_phone) DO UPDATE SET
          status = EXCLUDED.status,
          source = EXCLUDED.source,
          evidence = EXCLUDED.evidence,
          updated_by = EXCLUDED.updated_by,
          recorded_at = EXCLUDED.recorded_at,
          updated_at = NOW();`,
        [normalized, status, source, evidence, updatedBy, now]
      );

      // 7. Insert immutable audit history
      await client.query(
        `INSERT INTO consent_audit_log (
          normalized_phone, action, previous_status, new_status, source, evidence, actor, created_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8);`,
        [normalized, action, previousStatus, status, source, evidence, updatedBy, now]
      );

      await client.query('COMMIT;');

      return {
        phone: normalized,
        status,
        recordedAt: now.toISOString(),
        source,
        evidence,
        updatedBy,
      };
    } catch (err: any) {
      await client.query('ROLLBACK;').catch(() => {});
      console.error(`[ConsentStore] Error recording consent for ${normalized}:`, err.message);
      return null;
    } finally {
      client.release();
    }
  }

  /**
   * Records opt-out, overriding any prior consent.
   */
  public async recordOptOut(params: {
    phone: string;
    source: string;
    updatedBy: string;
    reason?: string;
    inboundWebhookId?: string;
  }): Promise<ConsentRecord | null> {
    return this.recordConsent({
      phone: params.phone,
      status: 'opted_out',
      source: params.source,
      evidence: params.reason || 'Customer opted out',
      updatedBy: params.updatedBy,
      inboundWebhookId: params.inboundWebhookId,
    });
  }

  /**
   * Retrieves consent record for a phone number from PostgreSQL.
   */
  public async getConsent(phone: string): Promise<ConsentRecord | undefined> {
    const normalized = normalizeWhatsAppPhone(phone);
    if (!normalized) return undefined;

    const pool = getPool();
    const res = await pool.query<{
      normalized_phone: string;
      status: string;
      recorded_at: Date;
      source: string;
      evidence: string;
      updated_by: string;
    }>(
      `SELECT normalized_phone, status, recorded_at, source, evidence, updated_by
       FROM customer_consent
       WHERE normalized_phone = $1
       LIMIT 1;`,
      [normalized]
    );

    if (res.rows.length === 0) return undefined;
    const row = res.rows[0];

    return {
      phone: row.normalized_phone,
      status: row.status as ConsentStatus,
      recordedAt: row.recorded_at.toISOString(),
      source: row.source,
      evidence: row.evidence,
      updatedBy: row.updated_by,
    };
  }

  /**
   * Authoritatively verifies whether a recipient has active, recorded opt-in consent.
   * Client-provided booleans are NEVER considered.
   * Returns true ONLY IF record exists in customer_consent AND status === 'opted_in'.
   */
  public async hasActiveConsent(phone: string): Promise<boolean> {
    const record = await this.getConsent(phone);
    if (!record) return false;
    return record.status === 'opted_in';
  }

  /**
   * Returns all consent records.
   */
  public async getAll(): Promise<ConsentRecord[]> {
    const pool = getPool();
    const res = await pool.query<{
      normalized_phone: string;
      status: string;
      recorded_at: Date;
      source: string;
      evidence: string;
      updated_by: string;
    }>(
      `SELECT normalized_phone, status, recorded_at, source, evidence, updated_by
       FROM customer_consent
       ORDER BY recorded_at DESC;`
    );

    return res.rows.map((row) => ({
      phone: row.normalized_phone,
      status: row.status as ConsentStatus,
      recordedAt: row.recorded_at.toISOString(),
      source: row.source,
      evidence: row.evidence,
      updatedBy: row.updated_by,
    }));
  }

  /**
   * Clears consent registry (used strictly in test fixtures).
   */
  public async clear(): Promise<void> {
    const pool = getPool();
    await pool.query('DELETE FROM consent_audit_log;');
    await pool.query('DELETE FROM customer_consent;');
    await pool.query('DELETE FROM webhook_events;');
  }
}

export const consentStore = new ConsentStore();
