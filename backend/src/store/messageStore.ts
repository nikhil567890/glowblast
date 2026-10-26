import { getPool } from '../db/pool';
import { StoredMessage, MessageStatus } from '../types/message';
import { INITIAL_BUSINESS_ID } from '../middleware/authMiddleware';

const STATUS_PRECEDENCE: Record<MessageStatus, number> = {
  queued: 0,
  sending: 1,
  uncertain_timeout: 1,
  accepted: 2,
  sent: 3,
  delivered: 4,
  read: 5,
  failed: 10,
  excluded_opt_out: 10,
};

export class MessageStore {
  /**
   * Fetches a message by its internal ID (e.g. campaignId_localCustomerId) from PostgreSQL.
   */
  public async get(id: string, businessId?: string): Promise<StoredMessage | undefined> {
    const pool = getPool();
    let row: any;

    try {
      let query = `
        SELECT id, campaign_id, local_customer_id, recipient_name, normalized_phone, status,
               provider_message_id, template_name, template_language,
               error_code, error_title, error_message, error_details, replied_at, created_at, updated_at
        FROM campaign_messages
        WHERE id = $1
      `;
      const params: any[] = [id];

      if (businessId) {
        query += ` AND (business_id = $2 OR (business_id IS NULL AND $2 = 'a0000000-0000-4000-8000-000000000001'))`;
        params.push(businessId);
      }
      query += ` LIMIT 1;`;

      const res = await pool.query<{
        id: string;
        campaign_id: string;
        local_customer_id: string;
        recipient_name: string;
        normalized_phone: string;
        status: string;
        provider_message_id: string | null;
        template_name: string | null;
        template_language: string | null;
        error_code: number | null;
        error_title: string | null;
        error_message: string | null;
        error_details: string | null;
        replied_at: Date | null;
        created_at: Date;
        updated_at: Date;
      }>(query, params);

      if (res.rows.length === 0) return undefined;
      row = res.rows[0];
    } catch (err: any) {
      if (err.code === '42703' || (err.message && err.message.toLowerCase().includes('replied_at'))) {
        if (businessId && businessId !== INITIAL_BUSINESS_ID) {
          return undefined;
        }
        console.warn(`[MessageStore] 'replied_at' or 'business_id' column missing in database. Falling back to legacy query.`);
        const fallback = await pool.query<any>(
          `SELECT id, campaign_id, local_customer_id, recipient_name, normalized_phone, status,
                  provider_message_id, template_name, template_language,
                  error_code, error_title, error_message, error_details, NULL AS replied_at, created_at, updated_at
           FROM campaign_messages
           WHERE id = $1
           LIMIT 1;`,
          [id]
        );
        if (fallback.rows.length === 0) return undefined;
        row = fallback.rows[0];
      } else {
        throw err;
      }
    }

    return this.mapRowToMessage(row);
  }

  /**
   * Fetches a message by Meta's providerMessageId (wamid), optionally scoped by businessId.
   */
  public async getByProviderId(providerMessageId: string, businessId?: string): Promise<StoredMessage | undefined> {
    const pool = getPool();
    let row: any;

    try {
      let query = `
        SELECT id, campaign_id, local_customer_id, recipient_name, normalized_phone, status,
               provider_message_id, template_name, template_language,
               error_code, error_title, error_message, error_details, replied_at, created_at, updated_at
        FROM campaign_messages
        WHERE provider_message_id = $1
      `;
      const params: any[] = [providerMessageId];

      if (businessId) {
        query += ` AND (business_id = $2 OR (business_id IS NULL AND $2 = 'a0000000-0000-4000-8000-000000000001'))`;
        params.push(businessId);
      }
      query += ` LIMIT 1;`;

      const res = await pool.query(query, params);

      if (res.rows.length === 0) return undefined;
      row = res.rows[0];
    } catch (err: any) {
      if (err.code === '42703' || (err.message && err.message.toLowerCase().includes('replied_at'))) {
        if (businessId && businessId !== INITIAL_BUSINESS_ID) {
          return undefined;
        }
        const fallback = await pool.query(
          `SELECT id, campaign_id, local_customer_id, recipient_name, normalized_phone, status,
                  provider_message_id, template_name, template_language,
                  error_code, error_title, error_message, error_details, NULL AS replied_at, created_at, updated_at
           FROM campaign_messages
           WHERE provider_message_id = $1
           LIMIT 1;`,
          [providerMessageId]
        );
        if (fallback.rows.length === 0) return undefined;
        row = fallback.rows[0];
      } else {
        throw err;
      }
    }

    return this.mapRowToMessage(row);
  }

  /**
   * Fetches all messages for a campaign from PostgreSQL.
   */
  public async getByCampaignId(campaignId: string): Promise<StoredMessage[]> {
    const pool = getPool();
    let rows: any[];

    try {
      const res = await pool.query(
        `SELECT id, campaign_id, local_customer_id, recipient_name, normalized_phone, status,
                provider_message_id, template_name, template_language,
                error_code, error_title, error_message, error_details, replied_at, created_at, updated_at
         FROM campaign_messages
         WHERE campaign_id = $1
         ORDER BY created_at ASC;`,
        [campaignId]
      );
      rows = res.rows;
    } catch (err: any) {
      if (err.code === '42703' || (err.message && err.message.toLowerCase().includes('replied_at'))) {
        const fallback = await pool.query(
          `SELECT id, campaign_id, local_customer_id, recipient_name, normalized_phone, status,
                  provider_message_id, template_name, template_language,
                  error_code, error_title, error_message, error_details, NULL AS replied_at, created_at, updated_at
           FROM campaign_messages
           WHERE campaign_id = $1
           ORDER BY created_at ASC;`,
          [campaignId]
        );
        rows = fallback.rows;
      } else {
        throw err;
      }
    }

    return rows.map((r) => this.mapRowToMessage(r));
  }

  /**
   * Atomically claims a queued message for dispatch.
   * Ensures that concurrent workers or HTTP handlers cannot dispatch the same message twice.
   * Returns the message if successfully claimed, or null if already claimed/sent.
   */
  public async claimQueuedMessage(id: string): Promise<StoredMessage | null> {
    const pool = getPool();
    const res = await pool.query(
      `UPDATE campaign_messages
       SET status = 'sending', updated_at = NOW()
       WHERE id = $1 AND status = 'queued'
       RETURNING id, campaign_id, local_customer_id, recipient_name, normalized_phone, status,
                 provider_message_id, template_name, template_language,
                 error_code, error_title, error_message, error_details, created_at, updated_at;`,
      [id]
    );

    if (res.rows.length === 0) return null;
    return this.mapRowToMessage(res.rows[0]);
  }

  /**
   * Upserts a message into PostgreSQL.
   */
  public async upsert(msg: StoredMessage): Promise<StoredMessage> {
    const pool = getPool();
    // Ensure parent campaign exists (for standalone message tests or out-of-order writes)
    await pool.query(
      `INSERT INTO campaigns (campaign_id, campaign_name, mode, status, template_name)
       VALUES ($1, 'Auto-created Campaign', 'test', 'processing', 'default')
       ON CONFLICT (campaign_id) DO NOTHING;`,
      [msg.campaignId]
    );

    let res;
    try {
      res = await pool.query(
        `INSERT INTO campaign_messages (
          id, campaign_id, local_customer_id, recipient_name, normalized_phone, status,
          provider_message_id, template_name, template_language,
          error_code, error_title, error_message, error_details, business_id, created_at, updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, NOW())
        ON CONFLICT (id) DO UPDATE SET
          status = EXCLUDED.status,
          provider_message_id = COALESCE(EXCLUDED.provider_message_id, campaign_messages.provider_message_id),
          template_name = COALESCE(EXCLUDED.template_name, campaign_messages.template_name),
          template_language = COALESCE(EXCLUDED.template_language, campaign_messages.template_language),
          error_code = COALESCE(EXCLUDED.error_code, campaign_messages.error_code),
          error_title = COALESCE(EXCLUDED.error_title, campaign_messages.error_title),
          error_message = COALESCE(EXCLUDED.error_message, campaign_messages.error_message),
          error_details = COALESCE(EXCLUDED.error_details, campaign_messages.error_details),
          business_id = COALESCE(EXCLUDED.business_id, campaign_messages.business_id),
          updated_at = NOW()
        RETURNING id, campaign_id, local_customer_id, recipient_name, normalized_phone, status,
                  provider_message_id, template_name, template_language,
                  error_code, error_title, error_message, error_details, business_id, created_at, updated_at;`,
        [
          msg.id,
          msg.campaignId,
          msg.localCustomerId,
          msg.recipientName,
          msg.normalizedPhone,
          msg.status,
          msg.providerMessageId || null,
          msg.templateName || null,
          msg.templateLanguage || null,
          msg.errorCode || null,
          msg.errorTitle || null,
          msg.errorMessage || null,
          msg.errorDetails || null,
          msg.businessId || null,
          msg.createdAt ? new Date(msg.createdAt) : new Date(),
        ]
      );
    } catch (err: any) {
      if (err.code === '42703') {
        if (msg.businessId && msg.businessId !== INITIAL_BUSINESS_ID) {
          throw new Error('Multi-business schema migration required for non-initial business message saving.');
        }
        res = await pool.query(
          `INSERT INTO campaign_messages (
            id, campaign_id, local_customer_id, recipient_name, normalized_phone, status,
            provider_message_id, template_name, template_language,
            error_code, error_title, error_message, error_details, created_at, updated_at
          )
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, NOW())
          ON CONFLICT (id) DO UPDATE SET
            status = EXCLUDED.status,
            provider_message_id = COALESCE(EXCLUDED.provider_message_id, campaign_messages.provider_message_id),
            template_name = COALESCE(EXCLUDED.template_name, campaign_messages.template_name),
            template_language = COALESCE(EXCLUDED.template_language, campaign_messages.template_language),
            error_code = COALESCE(EXCLUDED.error_code, campaign_messages.error_code),
            error_title = COALESCE(EXCLUDED.error_title, campaign_messages.error_title),
            error_message = COALESCE(EXCLUDED.error_message, campaign_messages.error_message),
            error_details = COALESCE(EXCLUDED.error_details, campaign_messages.error_details),
            updated_at = NOW()
          RETURNING id, campaign_id, local_customer_id, recipient_name, normalized_phone, status,
                    provider_message_id, template_name, template_language,
                    error_code, error_title, error_message, error_details, created_at, updated_at;`,
          [
            msg.id,
            msg.campaignId,
            msg.localCustomerId,
            msg.recipientName,
            msg.normalizedPhone,
            msg.status,
            msg.providerMessageId || null,
            msg.templateName || null,
            msg.templateLanguage || null,
            msg.errorCode || null,
            msg.errorTitle || null,
            msg.errorMessage || null,
            msg.errorDetails || null,
            msg.createdAt ? new Date(msg.createdAt) : new Date(),
          ]
        );
      } else {
        throw err;
      }
    }

    return this.mapRowToMessage(res.rows[0]);
  }

  /**
   * Updates message status enforcing monotonic progression.
   * Prevents delayed webhooks from downgrading a higher status (e.g. read cannot revert to delivered).
   * Supports 'uncertain_timeout' status.
   */
  public async updateStatus(
    id: string,
    status: MessageStatus,
    providerMessageId?: string,
    error?: { code?: number; title?: string; message?: string; details?: string }
  ): Promise<StoredMessage | undefined> {
    const pool = getPool();

    const currentMsg = await this.get(id);
    if (!currentMsg) return undefined;

    const currentWeight = STATUS_PRECEDENCE[currentMsg.status] ?? 0;
    const newWeight = STATUS_PRECEDENCE[status] ?? 0;

    const isTerminal = status === 'failed' || status === 'excluded_opt_out';
    const isCurrentTerminal = currentMsg.status === 'failed' || currentMsg.status === 'excluded_opt_out';

    if (isCurrentTerminal && !isTerminal) {
      console.log(`[MessageStore] Preserving terminal status '${currentMsg.status}' for ${id}`);
      return currentMsg;
    }

    if (newWeight < currentWeight && !isTerminal) {
      console.log(`[MessageStore] Preserving higher status '${currentMsg.status}' over '${status}' for ${id}`);
      return currentMsg;
    }

    const res = await pool.query(
      `UPDATE campaign_messages
       SET status = $2,
           provider_message_id = COALESCE($3, provider_message_id),
           error_code = COALESCE($4, error_code),
           error_title = COALESCE($5, error_title),
           error_message = COALESCE($6, error_message),
           error_details = COALESCE($7, error_details),
           updated_at = NOW()
       WHERE id = $1
       RETURNING id, campaign_id, local_customer_id, recipient_name, normalized_phone, status,
                 provider_message_id, template_name, template_language,
                 error_code, error_title, error_message, error_details, created_at, updated_at;`,
      [
        id,
        status,
        providerMessageId || null,
        error?.code || null,
        error?.title || null,
        error?.message || null,
        error?.details || null,
      ]
    );

    if (res.rows.length === 0) return undefined;
    return this.mapRowToMessage(res.rows[0]);
  }

  /**
   * Reconciles messages that were in flight ('sending') during a crash or restart.
   * Transitions them to 'uncertain_timeout' after thresholdMinutes (default 5 min).
   * They will NOT be automatically resent.
   */
  public async reconcileInFlightMessages(thresholdMinutes: number = 5): Promise<number> {
    const pool = getPool();
    const res = await pool.query(
      `UPDATE campaign_messages
       SET status = 'uncertain_timeout',
           error_code = 504,
           error_title = 'Worker Crash Recovery',
           error_message = 'Process terminated while send was in-flight. Automatic resend prohibited.',
           updated_at = NOW()
       WHERE status = 'sending' AND updated_at < NOW() - ($1 || ' minutes')::interval
       RETURNING id;`,
      [thresholdMinutes]
    );

    return res.rowCount || 0;
  }

  /**
   * Idempotently records an inbound WhatsApp reply timestamp on the message.
   * Returns true if newly marked, false if already marked.
   */
  public async recordReply(id: string): Promise<boolean> {
    const pool = getPool();
    try {
      const res = await pool.query(
        `UPDATE campaign_messages
         SET replied_at = NOW(), updated_at = NOW()
         WHERE id = $1 AND replied_at IS NULL
         RETURNING id;`,
        [id]
      );
      return (res.rowCount || 0) > 0;
    } catch (err: any) {
      if (err.code === '42703' || (err.message && err.message.toLowerCase().includes('replied_at'))) {
        console.warn(`[MessageStore] 'replied_at' column missing in database. Cannot record reply timestamp.`);
        return false;
      }
      throw err;
    }
  }

  /**
   * Clears messages table (used strictly in test fixtures).
   */
  public async clear(): Promise<void> {
    const pool = getPool();
    await pool.query('DELETE FROM campaign_messages;');
  }

  private mapRowToMessage(row: any): StoredMessage {
    return {
      id: row.id,
      campaignId: row.campaign_id,
      businessId: row.business_id || undefined,
      localCustomerId: row.local_customer_id,
      recipientName: row.recipient_name,
      normalizedPhone: row.normalized_phone,
      status: row.status as MessageStatus,
      providerMessageId: row.provider_message_id || undefined,
      templateName: row.template_name || undefined,
      templateLanguage: row.template_language || undefined,
      errorCode: row.error_code ?? undefined,
      errorTitle: row.error_title || undefined,
      errorMessage: row.error_message || undefined,
      errorDetails: row.error_details || undefined,
      repliedAt: row.replied_at ? new Date(row.replied_at).toISOString() : undefined,
      createdAt: row.created_at ? new Date(row.created_at).toISOString() : new Date().toISOString(),
      updatedAt: row.updated_at ? new Date(row.updated_at).toISOString() : new Date().toISOString(),
    };
  }
}

export const messageStore = new MessageStore();
