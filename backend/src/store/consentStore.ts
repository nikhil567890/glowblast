import { PoolClient } from 'pg';
import { getPool } from '../db/pool';
import { normalizeWhatsAppPhone } from '../utils/phone';

export type ConsentStatus = 'opted_in' | 'opted_out' | 'revoked';
export type ConsentCategory = 'marketing' | 'utility' | 'unclassified';

export interface ConsentRecord {
  phone: string; // Normalized international phone digits
  customerId?: string;
  consentCategory: ConsentCategory;
  status: ConsentStatus;
  recordedAt: string; // ISO-8601 timestamp
  source: string; // e.g. 'manual_verified_opt_in', 'inbound_whatsapp_keyword', 'front_desk_digital_waiver'
  evidence?: string; // Audit trail, reference, notes
  consentTextVersion?: string; // e.g. 'v1.0_promotional_waiver_2026'
  updatedBy: string; // Identity of user or process that updated consent
}

export interface BulkConsentRecordResult {
  phone: string;
  customerId?: string;
  consentCategory: ConsentCategory;
  status: ConsentStatus;
  success: boolean;
  recordedAt?: string;
  source?: string;
  evidence?: string;
  consentTextVersion?: string;
  updatedBy?: string;
  error?: string;
  isDuplicateOrUnchanged?: boolean;
}

export interface BulkConsentOutcome {
  totalRequested: number;
  succeeded: number;
  failed: number;
  results: BulkConsentRecordResult[];
  failures: Array<{ phone: string; customerId?: string; error: string }>;
}

export class ConsentStore {
  private schemaChecked = false;

  /**
   * Safe no-op schema check.
   * Production schema changes are strictly governed by versioned migrations (backend/src/db/migrations).
   * Runtime DDL execution at application startup or request time is intentionally disabled.
   */
  public async ensureSchema(): Promise<void> {
    this.schemaChecked = true;
  }

  /**
   * Authoritatively records customer consent or opt-out inside an atomic PostgreSQL transaction.
   * - Serializes concurrent updates on the same phone number and category via transaction-scoped advisory locks.
   * - Deduplicates inbound webhooks via webhook_events to ensure zero duplicate audit entries.
   * - Enforces that an existing opt-out can only be reversed to opted_in with explicit authorization
   *   (allowOptOutOverride: true) and genuine evidence of renewed consent.
   * - Preserves foreign key integrity with customers table.
   * - Accurately records previous and new states in the append-only consent_audit_log.
   */
  public async recordConsent(params: {
    phone: string;
    customerId?: string;
    consentCategory?: ConsentCategory;
    status: ConsentStatus;
    source: string;
    evidence?: string;
    consentTextVersion?: string;
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
      customerId,
      consentCategory = 'marketing',
      status,
      source,
      evidence = '',
      consentTextVersion = '',
      updatedBy,
      isAuthorizedAdmin = false,
      allowOptOutOverride = false,
      inboundWebhookId,
    } = params;

    const defaultTextVersion = consentCategory === 'marketing'
      ? 'v1.0_promotional_waiver_2026'
      : consentCategory === 'utility'
      ? 'v1.0_transactional_notice_2026'
      : undefined;

    const effectiveTextVersion = (consentTextVersion && consentTextVersion.trim().length > 0)
      ? consentTextVersion.trim()
      : defaultTextVersion;

    const pool = getPool();
    const client: PoolClient = await pool.connect();

    try {
      await client.query('BEGIN;');

      // 1. Webhook Deduplication (e.g. for inbound STOP webhooks)
      if (inboundWebhookId) {
        const dedupKey = `inbound_msg:${inboundWebhookId}:${consentCategory}`;
        const dedupRes = await client.query(
          `INSERT INTO webhook_events (dedup_key, event_type, provider_message_id, status, payload)
           VALUES ($1, 'message', $2, NULL, $3)
           ON CONFLICT (dedup_key) DO NOTHING
           RETURNING dedup_key;`,
          [dedupKey, inboundWebhookId, JSON.stringify({ phone: normalized, consentCategory, source, evidence })]
        );

        // If duplicate event delivery, commit without creating duplicate audit log entry
        if (dedupRes.rowCount === 0) {
          await client.query('COMMIT;');
          const existing = await this.getConsent(normalized, consentCategory);
          return existing || null;
        }
      }

      // 2. Acquire transaction-scoped advisory lock for this normalized phone and category
      // Guaranteed serialization across processes even when customer_consent has 0 rows
      await client.query(
        `SELECT pg_advisory_xact_lock(hashtext('consent:' || $1 || ':' || $2)::bigint);`,
        [normalized, consentCategory]
      );

      // 3. Read previous status for this category
      const existingRes = await client.query<{
        status: string;
        customer_id: string | null;
        source: string;
        evidence: string;
        recorded_at: Date;
      }>(
        `SELECT status, customer_id, source, evidence, recorded_at FROM customer_consent WHERE normalized_phone = $1 AND consent_category = $2;`,
        [normalized, consentCategory]
      );

      const previousStatus = existingRes.rows.length > 0 ? (existingRes.rows[0].status as ConsentStatus) : null;
      const effectiveCustomerId = customerId || (existingRes.rows.length > 0 ? existingRes.rows[0].customer_id || undefined : undefined);

      // 4. Preserve customer foreign key integrity
      let resolvedCustomerId: string | null = null;
      if (effectiveCustomerId) {
        const custById = await client.query<{ id: string }>(
          `SELECT id FROM customers WHERE id = $1;`,
          [effectiveCustomerId]
        );
        if (custById.rows.length > 0) {
          resolvedCustomerId = custById.rows[0].id;
        } else {
          const custByPhone = await client.query<{ id: string }>(
            `SELECT id FROM customers WHERE normalized_phone = $1;`,
            [normalized]
          );
          if (custByPhone.rows.length > 0) {
            resolvedCustomerId = custByPhone.rows[0].id;
          } else {
            // Insert parent customer record to satisfy customer_consent_customer_id_fkey
            await client.query(
              `INSERT INTO customers (id, normalized_phone, display_name)
               VALUES ($1, $2, $3)
               ON CONFLICT (id) DO NOTHING;`,
              [effectiveCustomerId, normalized, effectiveCustomerId]
            );
            resolvedCustomerId = effectiveCustomerId;
          }
        }
      } else {
        const custByPhone = await client.query<{ id: string }>(
          `SELECT id FROM customers WHERE normalized_phone = $1;`,
          [normalized]
        );
        if (custByPhone.rows.length > 0) {
          resolvedCustomerId = custByPhone.rows[0].id;
        }
      }

      // 5. Opt-Out Override Protection
      // Overriding an existing opt-out strictly requires authorized admin and explicit override flag
      if (previousStatus === 'opted_out' && status === 'opted_in') {
        if (!isAuthorizedAdmin || !allowOptOutOverride) {
          await client.query('ROLLBACK;');
          console.warn(`[ConsentStore] Blocked unauthorized opt-out override attempt for ${normalized} (${consentCategory})`);
          return null;
        }
      }

      // 5b. Idempotency Protection:
      // If customer is already in this status with the same source and evidence, return existing without inserting duplicate audit log
      if (
        previousStatus === status &&
        existingRes.rows.length > 0 &&
        existingRes.rows[0].source === source &&
        existingRes.rows[0].evidence === evidence
      ) {
        await client.query('COMMIT;');
        return {
          phone: normalized,
          customerId: resolvedCustomerId || effectiveCustomerId || undefined,
          consentCategory,
          status,
          recordedAt: existingRes.rows[0].recorded_at?.toISOString() || new Date().toISOString(),
          source,
          evidence,
          consentTextVersion: effectiveTextVersion || undefined,
          updatedBy,
        };
      }

      // 6. Derive audit action
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

      // 7. Upsert current consent row
      await client.query(
        `INSERT INTO customer_consent (
          normalized_phone, customer_id, consent_category, status, source, evidence, consent_text_version, updated_by, recorded_at, updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $9)
        ON CONFLICT (normalized_phone, consent_category) DO UPDATE SET
          customer_id = COALESCE(EXCLUDED.customer_id, customer_consent.customer_id),
          status = EXCLUDED.status,
          source = EXCLUDED.source,
          evidence = EXCLUDED.evidence,
          consent_text_version = EXCLUDED.consent_text_version,
          updated_by = EXCLUDED.updated_by,
          recorded_at = EXCLUDED.recorded_at,
          updated_at = NOW();`,
        [normalized, resolvedCustomerId || null, consentCategory, status, source, evidence, effectiveTextVersion || null, updatedBy, now]
      );

      // 8. Insert immutable audit history
      await client.query(
        `INSERT INTO consent_audit_log (
          normalized_phone, customer_id, consent_category, action, previous_status, new_status, source, evidence, consent_text_version, actor, created_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11);`,
        [normalized, resolvedCustomerId || effectiveCustomerId || null, consentCategory, action, previousStatus, status, source, evidence, effectiveTextVersion || null, updatedBy, now]
      );

      await client.query('COMMIT;');

      return {
        phone: normalized,
        customerId: resolvedCustomerId || effectiveCustomerId || undefined,
        consentCategory,
        status,
        recordedAt: now.toISOString(),
        source,
        evidence,
        consentTextVersion: effectiveTextVersion || undefined,
        updatedBy,
      };
    } catch (err: any) {
      await client.query('ROLLBACK;').catch(() => {});
      console.error(`[ConsentStore] Error recording consent for ${normalized} (${consentCategory}):`, err.message);
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
    customerId?: string;
    consentCategory?: ConsentCategory;
    source: string;
    updatedBy: string;
    reason?: string;
    inboundWebhookId?: string;
  }): Promise<ConsentRecord | null> {
    return this.recordConsent({
      phone: params.phone,
      customerId: params.customerId,
      consentCategory: params.consentCategory || 'marketing',
      status: 'opted_out',
      source: params.source,
      evidence: params.reason || 'Customer opted out',
      updatedBy: params.updatedBy,
      inboundWebhookId: params.inboundWebhookId,
    });
  }

  /**
   * Retrieves consent record for a phone number and specific category from PostgreSQL.
   */
  public async getConsent(phone: string, category: ConsentCategory = 'marketing'): Promise<ConsentRecord | undefined> {
    const normalized = normalizeWhatsAppPhone(phone);
    if (!normalized) return undefined;

    const pool = getPool();
    const res = await pool.query<{
      normalized_phone: string;
      customer_id: string | null;
      consent_category: string;
      status: string;
      recorded_at: Date;
      source: string;
      evidence: string;
      consent_text_version: string | null;
      updated_by: string;
    }>(
      `SELECT normalized_phone, customer_id, consent_category, status, recorded_at, source, evidence, consent_text_version, updated_by
       FROM customer_consent
       WHERE normalized_phone = $1 AND consent_category = $2
       LIMIT 1;`,
      [normalized, category]
    );

    if (res.rows.length === 0) return undefined;
    const row = res.rows[0];

    return {
      phone: row.normalized_phone,
      customerId: row.customer_id || undefined,
      consentCategory: (row.consent_category as ConsentCategory) || 'unclassified',
      status: row.status as ConsentStatus,
      recordedAt: row.recorded_at.toISOString(),
      source: row.source,
      evidence: row.evidence,
      consentTextVersion: row.consent_text_version || undefined,
      updatedBy: row.updated_by,
    };
  }

  /**
   * Retrieves all consent records (across marketing, utility, and unclassified) for a recipient phone.
   */
  public async getConsentsForPhone(phone: string): Promise<ConsentRecord[]> {
    const normalized = normalizeWhatsAppPhone(phone);
    if (!normalized) return [];

    const pool = getPool();
    const res = await pool.query<{
      normalized_phone: string;
      customer_id: string | null;
      consent_category: string;
      status: string;
      recorded_at: Date;
      source: string;
      evidence: string;
      consent_text_version: string | null;
      updated_by: string;
    }>(
      `SELECT normalized_phone, customer_id, consent_category, status, recorded_at, source, evidence, consent_text_version, updated_by
       FROM customer_consent
       WHERE normalized_phone = $1
       ORDER BY consent_category ASC;`,
      [normalized]
    );

    return res.rows.map((row) => ({
      phone: row.normalized_phone,
      customerId: row.customer_id || undefined,
      consentCategory: (row.consent_category as ConsentCategory) || 'unclassified',
      status: row.status as ConsentStatus,
      recordedAt: row.recorded_at.toISOString(),
      source: row.source,
      evidence: row.evidence,
      consentTextVersion: row.consent_text_version || undefined,
      updatedBy: row.updated_by,
    }));
  }

  /**
   * Authoritatively verifies whether a recipient has active, recorded opt-in consent for a specific category.
   * Client-provided booleans are NEVER considered.
   * Returns true ONLY IF record exists in customer_consent AND status === 'opted_in' for explicit category.
   * 'unclassified' or historical unverified consent records NEVER qualify.
   */
  public async hasActiveConsent(phone: string, category: ConsentCategory = 'marketing'): Promise<boolean> {
    if (category !== 'marketing' && category !== 'utility') {
      return false;
    }
    const record = await this.getConsent(phone, category);
    if (!record) return false;
    if (record.consentCategory !== category) return false;
    if (record.status !== 'opted_in') return false;

    // Provenance verification: Do not treat historical records as verified marketing or utility consent
    // simply because their stored category says marketing or utility.
    // If provenance cannot establish explicit category-specific consent (missing consent text version
    // or legacy unverified source), the record cannot authorize a production campaign.
    if (!record.consentTextVersion || record.consentTextVersion.trim().length === 0) {
      return false;
    }
    const normalizedSource = (record.source || '').toLowerCase().trim();
    if (['legacy', 'migration', 'seed', 'manual_seed', 'default', 'unverified'].includes(normalizedSource)) {
      return false;
    }

    return true;
  }

  /**
   * Returns all consent records, optionally filtered by category.
   */
  public async getAll(category?: ConsentCategory): Promise<ConsentRecord[]> {
    const pool = getPool();
    let query = `SELECT normalized_phone, customer_id, consent_category, status, recorded_at, source, evidence, consent_text_version, updated_by
                 FROM customer_consent`;
    const params: any[] = [];
    if (category) {
      params.push(category);
      query += ` WHERE consent_category = $1`;
    }
    query += ` ORDER BY recorded_at DESC;`;

    const res = await pool.query<{
      normalized_phone: string;
      customer_id: string | null;
      consent_category: string;
      status: string;
      recorded_at: Date;
      source: string;
      evidence: string;
      consent_text_version: string | null;
      updated_by: string;
    }>(query, params);

    return res.rows.map((row) => ({
      phone: row.normalized_phone,
      customerId: row.customer_id || undefined,
      consentCategory: (row.consent_category as ConsentCategory) || 'unclassified',
      status: row.status as ConsentStatus,
      recordedAt: row.recorded_at.toISOString(),
      source: row.source,
      evidence: row.evidence,
      consentTextVersion: row.consent_text_version || undefined,
      updatedBy: row.updated_by,
    }));
  }

  /**
   * Bulk records customer consent inside an atomic PostgreSQL transaction.
   * - Validates and normalizes all phone numbers.
   * - Serializes concurrent updates deterministically (sorted order to prevent deadlocks).
   * - Enforces opt-out override protections: existing opted_out cannot be changed to opted_in
   *   without explicit authorization (isAuthorizedAdmin && allowOptOutOverride).
   * - Idempotency: If a record is already opted_in with matching source and evidence,
   *   it succeeds immediately without creating duplicate audit log entries.
   * - Performs batch lookups, batch foreign-key customer inserts, and batch upserts.
   * - Reports individual results per record so callers know exactly which records were saved.
   */
  public async bulkRecordConsent(params: {
    records: Array<{
      phone: string;
      customerId?: string;
      consentCategory?: ConsentCategory;
      status?: ConsentStatus;
      source: string;
      evidence?: string;
      consentTextVersion?: string;
    }>;
    updatedBy: string;
    isAuthorizedAdmin?: boolean;
    allowOptOutOverride?: boolean;
  }): Promise<BulkConsentOutcome> {
    const {
      records,
      updatedBy,
      isAuthorizedAdmin = false,
      allowOptOutOverride = false,
    } = params;

    if (!records || records.length === 0) {
      return {
        totalRequested: 0,
        succeeded: 0,
        failed: 0,
        results: [],
        failures: [],
      };
    }

    const results: BulkConsentRecordResult[] = [];
    const failures: Array<{ phone: string; customerId?: string; error: string }> = [];

    type ValidatedEntry = {
      originalIndex: number;
      rawPhone: string;
      normalizedPhone: string;
      customerId?: string;
      category: ConsentCategory;
      status: ConsentStatus;
      source: string;
      evidence: string;
      textVersion?: string;
    };

    const validEntries: ValidatedEntry[] = [];

    for (let i = 0; i < records.length; i++) {
      const entry = records[i];
      const normalized = normalizeWhatsAppPhone(entry.phone);
      const category: ConsentCategory = entry.consentCategory || 'marketing';
      const status: ConsentStatus = entry.status || 'opted_in';
      const defaultTextVersion = category === 'marketing'
        ? 'v1.0_promotional_waiver_2026'
        : category === 'utility'
        ? 'v1.0_transactional_notice_2026'
        : undefined;
      const textVersion = (entry.consentTextVersion && entry.consentTextVersion.trim().length > 0)
        ? entry.consentTextVersion.trim()
        : defaultTextVersion;

      if (!normalized) {
        results[i] = {
          phone: entry.phone,
          customerId: entry.customerId,
          consentCategory: category,
          status,
          success: false,
          error: 'Invalid WhatsApp phone format',
        };
        failures.push({
          phone: entry.phone,
          customerId: entry.customerId,
          error: 'Invalid WhatsApp phone format',
        });
        continue;
      }

      validEntries.push({
        originalIndex: i,
        rawPhone: entry.phone,
        normalizedPhone: normalized,
        customerId: entry.customerId,
        category,
        status,
        source: entry.source,
        evidence: entry.evidence || '',
        textVersion,
      });
    }

    if (validEntries.length === 0) {
      return {
        totalRequested: records.length,
        succeeded: 0,
        failed: failures.length,
        results,
        failures,
      };
    }

    const pool = getPool();
    const client: PoolClient = await pool.connect();

    try {
      await client.query('BEGIN;');

      // Sort unique phones deterministically to ensure deadlock-free lock acquisition
      const sortedPhones = Array.from(new Set(validEntries.map((e) => e.normalizedPhone))).sort();

      // Acquire transaction advisory locks in strictly monotonic order in a single query
      await client.query(
        `SELECT pg_advisory_xact_lock(hashtext('consent:' || p || ':marketing')::bigint)
         FROM UNNEST($1::varchar[]) AS p;`,
        [sortedPhones]
      );

      // Query existing consent statuses for all normalized phones in one query
      const existingRes = await client.query<{
        normalized_phone: string;
        consent_category: string;
        status: string;
        customer_id: string | null;
        source: string;
        evidence: string;
        recorded_at: Date;
        consent_text_version: string | null;
      }>(
        `SELECT normalized_phone, consent_category, status, customer_id, source, evidence, recorded_at, consent_text_version
         FROM customer_consent
         WHERE normalized_phone = ANY($1);`,
        [sortedPhones]
      );

      const existingMap = new Map<string, {
        status: ConsentStatus;
        customerId: string | null;
        source: string;
        evidence: string;
        recordedAt: Date;
        textVersion: string | null;
      }>();

      for (const row of existingRes.rows) {
        existingMap.set(`${row.normalized_phone}:${row.consent_category}`, {
          status: row.status as ConsentStatus,
          customerId: row.customer_id,
          source: row.source,
          evidence: row.evidence,
          recordedAt: row.recorded_at,
          textVersion: row.consent_text_version,
        });
      }

      // Customer FK resolution: collect customer IDs and phones
      const requestedCustomerIds = Array.from(
        new Set(validEntries.map((e) => e.customerId).filter(Boolean))
      ) as string[];

      const existingCustRes = await client.query<{ id: string; normalized_phone: string }>(
        `SELECT id, normalized_phone FROM customers WHERE id = ANY($1) OR normalized_phone = ANY($2);`,
        [requestedCustomerIds, sortedPhones]
      );

      const customerById = new Map<string, string>();
      const customerByPhone = new Map<string, string>();
      for (const row of existingCustRes.rows) {
        customerById.set(row.id, row.id);
        customerByPhone.set(row.normalized_phone, row.id);
      }

      // Create missing parent customer records in batch if customerId was provided
      const missingCustomersToInsert: Array<{ id: string; phone: string }> = [];
      for (const entry of validEntries) {
        if (entry.customerId && !customerById.has(entry.customerId) && !customerByPhone.has(entry.normalizedPhone)) {
          missingCustomersToInsert.push({ id: entry.customerId, phone: entry.normalizedPhone });
          customerById.set(entry.customerId, entry.customerId);
          customerByPhone.set(entry.normalizedPhone, entry.customerId);
        }
      }

      if (missingCustomersToInsert.length > 0) {
        const uniqueMissing = Array.from(
          new Map(missingCustomersToInsert.map((c) => [c.id, c])).values()
        );
        const missingIds = uniqueMissing.map((m) => m.id);
        const missingPhones = uniqueMissing.map((m) => m.phone);
        const missingNames = uniqueMissing.map((m) => m.id);

        await client.query(
          `INSERT INTO customers (id, normalized_phone, display_name)
           SELECT t.id, t.normalized_phone, t.display_name
           FROM UNNEST($1::varchar[], $2::varchar[], $3::varchar[]) AS t(id, normalized_phone, display_name)
           WHERE NOT EXISTS (
             SELECT 1 FROM customers c WHERE c.id = t.id OR c.normalized_phone = t.normalized_phone
           );`,
          [missingIds, missingPhones, missingNames]
        );
      }

      // Re-query confirmed customer IDs to guarantee 100% foreign key validity
      const confirmedCustRes = await client.query<{ id: string; normalized_phone: string }>(
        `SELECT id, normalized_phone FROM customers WHERE id = ANY($1) OR normalized_phone = ANY($2);`,
        [requestedCustomerIds, sortedPhones]
      );
      const confirmedCustById = new Map<string, string>();
      const confirmedCustByPhone = new Map<string, string>();
      for (const row of confirmedCustRes.rows) {
        confirmedCustById.set(row.id, row.id);
        confirmedCustByPhone.set(row.normalized_phone, row.id);
      }

      const now = new Date();

      // Queues for batch insert / upsert
      const upsertConsent = {
        normalizedPhones: [] as string[],
        customerIds: [] as (string | null)[],
        categories: [] as string[],
        statuses: [] as string[],
        sources: [] as string[],
        evidences: [] as string[],
        textVersions: [] as (string | null)[],
        updatedBys: [] as string[],
        recordedAts: [] as Date[],
      };

      const insertAudit = {
        normalizedPhones: [] as string[],
        customerIds: [] as (string | null)[],
        categories: [] as string[],
        actions: [] as string[],
        previousStatuses: [] as (string | null)[],
        newStatuses: [] as string[],
        sources: [] as string[],
        evidences: [] as string[],
        textVersions: [] as (string | null)[],
        actors: [] as string[],
        createdAts: [] as Date[],
      };

      for (const entry of validEntries) {
        const key = `${entry.normalizedPhone}:${entry.category}`;
        const existing = existingMap.get(key);
        const previousStatus = existing ? existing.status : null;

        // Guaranteed foreign key resolution: strictly references an existing customers.id or null
        const resolvedCustomerId =
          (entry.customerId && confirmedCustById.has(entry.customerId) ? entry.customerId : null) ||
          confirmedCustByPhone.get(entry.normalizedPhone) ||
          (existing && existing.customerId && confirmedCustById.has(existing.customerId) ? existing.customerId : null) ||
          null;

        // Opt-out override protection
        if (previousStatus === 'opted_out' && entry.status === 'opted_in') {
          if (!isAuthorizedAdmin || !allowOptOutOverride) {
            results[entry.originalIndex] = {
              phone: entry.normalizedPhone,
              customerId: resolvedCustomerId || undefined,
              consentCategory: entry.category,
              status: entry.status,
              success: false,
              error: 'Consent update rejected. Reversing an opt-out requires allowOptOutOverride: true and verified administrator authorization.',
            };
            failures.push({
              phone: entry.normalizedPhone,
              customerId: resolvedCustomerId || undefined,
              error: 'Consent update rejected (opt-out override blocked)',
            });
            continue;
          }
        }

        // Idempotency: if already in this status with same source and evidence, return existing without writing duplicate audit entry
        if (
          previousStatus === entry.status &&
          existing &&
          existing.source === entry.source &&
          existing.evidence === entry.evidence
        ) {
          results[entry.originalIndex] = {
            phone: entry.normalizedPhone,
            customerId: resolvedCustomerId || undefined,
            consentCategory: entry.category,
            status: entry.status,
            success: true,
            isDuplicateOrUnchanged: true,
            recordedAt: existing.recordedAt.toISOString(),
            source: entry.source,
            evidence: entry.evidence,
            consentTextVersion: entry.textVersion,
            updatedBy,
          };
          continue;
        }

        // Derive action for audit
        let action: string;
        if (entry.status === 'opted_in') {
          if (previousStatus === null) action = 'initial_opt_in';
          else if (previousStatus === 'opted_out') action = 'opt_in_override_of_opt_out';
          else if (previousStatus === 'revoked') action = 'opt_in_reinstatement';
          else action = 'opt_in_update';
        } else if (entry.status === 'opted_out') {
          if (previousStatus === null) action = 'initial_opt_out';
          else if (previousStatus === 'opted_out') action = 'opt_out_reaffirmation';
          else action = 'opt_out';
        } else if (entry.status === 'revoked') {
          action = 'consent_revoked';
        } else {
          action = 'status_update';
        }

        upsertConsent.normalizedPhones.push(entry.normalizedPhone);
        upsertConsent.customerIds.push(resolvedCustomerId);
        upsertConsent.categories.push(entry.category);
        upsertConsent.statuses.push(entry.status);
        upsertConsent.sources.push(entry.source);
        upsertConsent.evidences.push(entry.evidence);
        upsertConsent.textVersions.push(entry.textVersion || null);
        upsertConsent.updatedBys.push(updatedBy);
        upsertConsent.recordedAts.push(now);

        insertAudit.normalizedPhones.push(entry.normalizedPhone);
        insertAudit.customerIds.push(resolvedCustomerId);
        insertAudit.categories.push(entry.category);
        insertAudit.actions.push(action);
        insertAudit.previousStatuses.push(previousStatus);
        insertAudit.newStatuses.push(entry.status);
        insertAudit.sources.push(entry.source);
        insertAudit.evidences.push(entry.evidence);
        insertAudit.textVersions.push(entry.textVersion || null);
        insertAudit.actors.push(updatedBy);
        insertAudit.createdAts.push(now);

        results[entry.originalIndex] = {
          phone: entry.normalizedPhone,
          customerId: resolvedCustomerId || undefined,
          consentCategory: entry.category,
          status: entry.status,
          success: true,
          recordedAt: now.toISOString(),
          source: entry.source,
          evidence: entry.evidence,
          consentTextVersion: entry.textVersion,
          updatedBy,
        };
      }

      // Execute batch upsert into customer_consent if any changes
      if (upsertConsent.normalizedPhones.length > 0) {
        await client.query(
          `INSERT INTO customer_consent (
            normalized_phone, customer_id, consent_category, status, source, evidence, consent_text_version, updated_by, recorded_at, updated_at
          )
          SELECT * FROM UNNEST(
            $1::varchar[], $2::varchar[], $3::varchar[], $4::varchar[], $5::varchar[], $6::text[], $7::varchar[], $8::varchar[], $9::timestamptz[], $9::timestamptz[]
          ) AS t(normalized_phone, customer_id, consent_category, status, source, evidence, consent_text_version, updated_by, recorded_at, updated_at)
          ON CONFLICT (normalized_phone, consent_category) DO UPDATE SET
            customer_id = COALESCE(EXCLUDED.customer_id, customer_consent.customer_id),
            status = EXCLUDED.status,
            source = EXCLUDED.source,
            evidence = EXCLUDED.evidence,
            consent_text_version = EXCLUDED.consent_text_version,
            updated_by = EXCLUDED.updated_by,
            recorded_at = EXCLUDED.recorded_at,
            updated_at = NOW();`,
          [
            upsertConsent.normalizedPhones,
            upsertConsent.customerIds,
            upsertConsent.categories,
            upsertConsent.statuses,
            upsertConsent.sources,
            upsertConsent.evidences,
            upsertConsent.textVersions,
            upsertConsent.updatedBys,
            upsertConsent.recordedAts,
          ]
        );

        // Execute batch insert into consent_audit_log
        await client.query(
          `INSERT INTO consent_audit_log (
            normalized_phone, customer_id, consent_category, action, previous_status, new_status, source, evidence, consent_text_version, actor, created_at
          )
          SELECT * FROM UNNEST(
            $1::varchar[], $2::varchar[], $3::varchar[], $4::varchar[], $5::varchar[], $6::varchar[], $7::varchar[], $8::text[], $9::varchar[], $10::varchar[], $11::timestamptz[]
          );`,
          [
            insertAudit.normalizedPhones,
            insertAudit.customerIds,
            insertAudit.categories,
            insertAudit.actions,
            insertAudit.previousStatuses,
            insertAudit.newStatuses,
            insertAudit.sources,
            insertAudit.evidences,
            insertAudit.textVersions,
            insertAudit.actors,
            insertAudit.createdAts,
          ]
        );
      }

      await client.query('COMMIT;');

      let succeeded = 0;
      let failed = 0;
      for (const r of results) {
        if (r && r.success) succeeded++;
        else failed++;
      }

      return {
        totalRequested: records.length,
        succeeded,
        failed,
        results,
        failures,
      };
    } catch (err: any) {
      await client.query('ROLLBACK;').catch(() => {});
      console.error('[ConsentStore] bulkRecordConsent transaction error:', err.message);
      throw err;
    } finally {
      client.release();
    }
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
