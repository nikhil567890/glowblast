import { getPool } from '../db/pool';
import { StoredCampaign, CampaignSummary, CampaignStatus } from '../types/campaign';
import { messageStore } from './messageStore';
import { INITIAL_BUSINESS_ID } from '../middleware/authMiddleware';

export class CampaignStore {
  public async get(campaignId: string, businessId?: string): Promise<StoredCampaign | undefined> {
    const pool = getPool();
    let row: any;

    try {
      let query = `SELECT campaign_id, client_request_token, campaign_name, status, template_name, template_language,
                          total_recipients, count_queued, count_accepted, count_sent, count_delivered,
                          count_read, count_replied, count_failed, count_excluded_opt_out, created_at, updated_at`;
      
      if (businessId) {
        query += `, business_id FROM campaigns
                  WHERE campaign_id = $1
                    AND (business_id = $2 OR (business_id IS NULL AND $2 = 'a0000000-0000-4000-8000-000000000001'))
                  LIMIT 1;`;
        const res = await pool.query(query, [campaignId, businessId]);
        if (res.rows.length === 0) return undefined;
        row = res.rows[0];
      } else {
        query += ` FROM campaigns WHERE campaign_id = $1 LIMIT 1;`;
        const res = await pool.query(query, [campaignId]);
        if (res.rows.length === 0) return undefined;
        row = res.rows[0];
      }
    } catch (err: any) {
      if (err.code === '42703' || (err.message && (err.message.includes('count_replied') || err.message.includes('business_id')))) {
        // Safe fail-closed compatibility: non-initial businesses have zero campaigns in unmigrated database
        if (businessId && businessId !== INITIAL_BUSINESS_ID) {
          return undefined;
        }
        // Fallback without count_replied or business_id
        const fallbackRes = await pool.query<any>(
          `SELECT campaign_id, client_request_token, campaign_name, status, template_name, template_language,
                  total_recipients, count_queued, count_accepted, count_sent, count_delivered,
                  count_read, 0 AS count_replied, count_failed, count_excluded_opt_out, created_at, updated_at
           FROM campaigns
           WHERE campaign_id = $1
           LIMIT 1;`,
          [campaignId]
        );
        if (fallbackRes.rows.length === 0) return undefined;
        row = fallbackRes.rows[0];
      } else {
        throw err;
      }
    }

    const messages = await messageStore.getByCampaignId(campaignId);

    const repliedCount =
      row.count_replied !== undefined && row.count_replied !== null
        ? Number(row.count_replied)
        : messages.filter((m) => !!m.repliedAt).length;

    return {
      campaignId: row.campaign_id,
      businessId: row.business_id || undefined,
      clientRequestToken: row.client_request_token || undefined,
      campaignName: row.campaign_name,
      status: row.status as CampaignStatus,
      templateName: row.template_name,
      templateLanguage: row.template_language,
      total: row.total_recipients,
      queued: row.count_queued,
      accepted: row.count_accepted,
      sent: row.count_sent,
      delivered: row.count_delivered,
      read: row.count_read,
      replied: repliedCount,
      failed: row.count_failed,
      excludedOptOut: row.count_excluded_opt_out,
      messages,
      createdAt: row.created_at instanceof Date ? row.created_at.toISOString() : new Date(row.created_at).toISOString(),
      updatedAt: row.updated_at instanceof Date ? row.updated_at.toISOString() : new Date(row.updated_at).toISOString(),
    };
  }

  public async getByClientRequestToken(token: string, businessId?: string): Promise<StoredCampaign | undefined> {
    const pool = getPool();
    let res;
    if (businessId) {
      try {
        res = await pool.query<{ campaign_id: string }>(
          `SELECT campaign_id FROM campaigns
           WHERE client_request_token = $1
             AND (business_id = $2 OR (business_id IS NULL AND $2 = 'a0000000-0000-4000-8000-000000000001'))
           LIMIT 1;`,
          [token, businessId]
        );
      } catch (err: any) {
        if (err.code === '42703') {
          if (businessId && businessId !== INITIAL_BUSINESS_ID) {
            return undefined;
          }
          res = await pool.query<{ campaign_id: string }>(
            `SELECT campaign_id FROM campaigns WHERE client_request_token = $1 LIMIT 1;`,
            [token]
          );
        } else {
          throw err;
        }
      }
    } else {
      res = await pool.query<{ campaign_id: string }>(
        `SELECT campaign_id FROM campaigns WHERE client_request_token = $1 LIMIT 1;`,
        [token]
      );
    }
    if (res.rows.length === 0) return undefined;
    return this.get(res.rows[0].campaign_id, businessId);
  }

  public async getSummary(campaignId: string, businessId?: string): Promise<CampaignSummary | undefined> {
    const camp = await this.get(campaignId, businessId);
    if (!camp) return undefined;

    // Recalculate summary metrics from actual messages in PostgreSQL
    const msgs = camp.messages;
    const queued = msgs.filter((m) => ['queued', 'sending'].includes(m.status)).length;
    const accepted = msgs.filter((m) =>
      ['accepted', 'sent', 'delivered', 'read'].includes(m.status)
    ).length;
    const sent = msgs.filter((m) => ['sent', 'delivered', 'read'].includes(m.status)).length;
    const delivered = msgs.filter((m) => ['delivered', 'read'].includes(m.status)).length;
    const read = msgs.filter((m) => m.status === 'read').length;
    const replied = msgs.filter((m) => !!m.repliedAt).length;
    const failed = msgs.filter((m) => ['failed', 'uncertain_timeout'].includes(m.status)).length;
    const excludedOptOut = msgs.filter((m) => m.status === 'excluded_opt_out').length;

    return {
      campaignId: camp.campaignId,
      businessId: camp.businessId,
      clientRequestToken: camp.clientRequestToken,
      campaignName: camp.campaignName,
      status: camp.status,
      templateName: camp.templateName,
      templateLanguage: camp.templateLanguage,
      total: camp.total,
      queued,
      accepted,
      sent,
      delivered,
      read,
      replied,
      failed,
      excludedOptOut,
      createdAt: camp.createdAt,
      updatedAt: camp.updatedAt,
    };
  }

  public async listSummaries(businessId?: string, limit: number = 50): Promise<CampaignSummary[]> {
    const pool = getPool();
    let rows: any[];

    if (businessId) {
      try {
        const res = await pool.query(
          `SELECT campaign_id, client_request_token, campaign_name, status, template_name, template_language,
                  total_recipients, count_queued, count_accepted, count_sent, count_delivered,
                  count_read, count_replied, count_failed, count_excluded_opt_out, business_id, created_at, updated_at
           FROM campaigns
           WHERE (business_id = $1 OR (business_id IS NULL AND $1 = 'a0000000-0000-4000-8000-000000000001'))
           ORDER BY created_at DESC
           LIMIT $2;`,
          [businessId, limit]
        );
        rows = res.rows;
      } catch (err: any) {
        if (err.code === '42703') {
          if (businessId && businessId !== INITIAL_BUSINESS_ID) {
            return [];
          }
          const fallbackRes = await pool.query(
            `SELECT campaign_id, client_request_token, campaign_name, status, template_name, template_language,
                    total_recipients, count_queued, count_accepted, count_sent, count_delivered,
                    count_read, 0 AS count_replied, count_failed, count_excluded_opt_out, created_at, updated_at
             FROM campaigns
             ORDER BY created_at DESC
             LIMIT $1;`,
            [limit]
          );
          rows = fallbackRes.rows;
        } else {
          throw err;
        }
      }
    } else {
      const res = await pool.query(
        `SELECT campaign_id, client_request_token, campaign_name, status, template_name, template_language,
                total_recipients, count_queued, count_accepted, count_sent, count_delivered,
                count_read, 0 AS count_replied, count_failed, count_excluded_opt_out, created_at, updated_at
         FROM campaigns
         ORDER BY created_at DESC
         LIMIT $1;`,
        [limit]
      );
      rows = res.rows;
    }

    return rows.map((row) => ({
      campaignId: row.campaign_id,
      businessId: row.business_id || undefined,
      clientRequestToken: row.client_request_token || undefined,
      campaignName: row.campaign_name,
      status: row.status as CampaignStatus,
      templateName: row.template_name,
      templateLanguage: row.template_language,
      total: row.total_recipients,
      queued: row.count_queued,
      accepted: row.count_accepted,
      sent: row.count_sent,
      delivered: row.count_delivered,
      read: row.count_read,
      replied: row.count_replied ? Number(row.count_replied) : 0,
      failed: row.count_failed,
      excludedOptOut: row.count_excluded_opt_out,
      createdAt: row.created_at instanceof Date ? row.created_at.toISOString() : new Date(row.created_at).toISOString(),
      updatedAt: row.updated_at instanceof Date ? row.updated_at.toISOString() : new Date(row.updated_at).toISOString(),
    }));
  }

  public async calculateCampaignStatus(campaignId: string, businessId?: string): Promise<CampaignStatus> {
    const camp = await this.get(campaignId, businessId);
    if (!camp) return 'failed';

    const msgs = camp.messages;
    const total = msgs.length;
    if (total === 0) return 'completed';

    const inFlight = msgs.filter((m) => ['queued', 'sending'].includes(m.status)).length;
    if (inFlight > 0) {
      return 'processing';
    }

    const failed = msgs.filter((m) => ['failed', 'uncertain_timeout'].includes(m.status)).length;
    const successful = msgs.filter((m) =>
      ['accepted', 'sent', 'delivered', 'read'].includes(m.status)
    ).length;

    if (successful === 0 && failed > 0) {
      return 'failed';
    } else if (failed > 0 && successful > 0) {
      return 'completed_with_errors';
    } else if (successful > 0 && failed === 0) {
      return 'completed';
    } else if (total === msgs.filter((m) => m.status === 'excluded_opt_out').length) {
      return 'completed_with_errors';
    }

    return 'completed';
  }

  public async recalculateAndSaveCampaignStatus(campaignId: string, businessId?: string): Promise<CampaignSummary | undefined> {
    const summary = await this.getSummary(campaignId, businessId);
    if (!summary) return undefined;

    const newStatus = await this.calculateCampaignStatus(campaignId, businessId);
    const pool = getPool();

    try {
      await pool.query(
        `UPDATE campaigns
         SET status = $2,
             count_queued = $3,
             count_accepted = $4,
             count_sent = $5,
             count_delivered = $6,
             count_read = $7,
             count_replied = $8,
             count_failed = $9,
             count_excluded_opt_out = $10,
             updated_at = NOW()
         WHERE campaign_id = $1
           AND ($11::uuid IS NULL OR business_id = $11::uuid OR (business_id IS NULL AND $11::uuid = 'a0000000-0000-4000-8000-000000000001'::uuid));`,
        [
          campaignId,
          newStatus,
          summary.queued,
          summary.accepted,
          summary.sent,
          summary.delivered,
          summary.read,
          summary.replied,
          summary.failed,
          summary.excludedOptOut,
          businessId || null,
        ]
      );
    } catch (err: any) {
      if (err.code === '42703' || (err.message && err.message.toLowerCase().includes('count_replied'))) {
        console.warn(`[CampaignStore] 'count_replied' or 'business_id' column missing during status update. Falling back to legacy update.`);
        await pool.query(
          `UPDATE campaigns
           SET status = $2,
               count_queued = $3,
               count_accepted = $4,
               count_sent = $5,
               count_delivered = $6,
               count_read = $7,
               count_failed = $8,
               count_excluded_opt_out = $9,
               updated_at = NOW()
           WHERE campaign_id = $1;`,
          [
            campaignId,
            newStatus,
            summary.queued,
            summary.accepted,
            summary.sent,
            summary.delivered,
            summary.read,
            summary.failed,
            summary.excludedOptOut,
          ]
        );
      } else {
        throw err;
      }
    }

    return {
      ...summary,
      status: newStatus,
      updatedAt: new Date().toISOString(),
    };
  }

  public async create(campaign: StoredCampaign, businessId?: string): Promise<StoredCampaign> {
    const pool = getPool();
    const effectiveBizId = businessId || campaign.businessId || null;

    try {
      await pool.query(
        `INSERT INTO campaigns (
          campaign_id, client_request_token, campaign_name, mode, status,
          template_name, template_language, total_recipients,
          count_queued, count_accepted, count_sent, count_delivered, count_read, count_failed, count_excluded_opt_out,
          business_id, created_at, updated_at
        )
        VALUES ($1, $2, $3, 'test', $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
        ON CONFLICT (campaign_id) DO UPDATE SET
          status = EXCLUDED.status,
          count_queued = EXCLUDED.count_queued,
          count_accepted = EXCLUDED.count_accepted,
          count_sent = EXCLUDED.count_sent,
          count_delivered = EXCLUDED.count_delivered,
          count_read = EXCLUDED.count_read,
          count_failed = EXCLUDED.count_failed,
          count_excluded_opt_out = EXCLUDED.count_excluded_opt_out,
          business_id = COALESCE(EXCLUDED.business_id, campaigns.business_id),
          updated_at = NOW();`,
        [
          campaign.campaignId,
          campaign.clientRequestToken || null,
          campaign.campaignName,
          campaign.status,
          campaign.templateName || 'hello_world',
          campaign.templateLanguage || 'en_US',
          campaign.total,
          campaign.queued,
          campaign.accepted,
          campaign.sent,
          campaign.delivered,
          campaign.read,
          campaign.failed,
          campaign.excludedOptOut,
          effectiveBizId,
          campaign.createdAt ? new Date(campaign.createdAt) : new Date(),
          campaign.updatedAt ? new Date(campaign.updatedAt) : new Date(),
        ]
      );
    } catch (err: any) {
      if (err.code === '42703') {
        if (effectiveBizId && effectiveBizId !== INITIAL_BUSINESS_ID) {
          throw new Error('Multi-business schema migration required for non-initial business campaign creation.');
        }
        await pool.query(
          `INSERT INTO campaigns (
            campaign_id, client_request_token, campaign_name, mode, status,
            template_name, template_language, total_recipients,
            count_queued, count_accepted, count_sent, count_delivered, count_read, count_failed, count_excluded_opt_out,
            created_at, updated_at
          )
          VALUES ($1, $2, $3, 'test', $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
          ON CONFLICT (campaign_id) DO UPDATE SET
            status = EXCLUDED.status,
            count_queued = EXCLUDED.count_queued,
            count_accepted = EXCLUDED.count_accepted,
            count_sent = EXCLUDED.count_sent,
            count_delivered = EXCLUDED.count_delivered,
            count_read = EXCLUDED.count_read,
            count_failed = EXCLUDED.count_failed,
            count_excluded_opt_out = EXCLUDED.count_excluded_opt_out,
            updated_at = NOW();`,
          [
            campaign.campaignId,
            campaign.clientRequestToken || null,
            campaign.campaignName,
            campaign.status,
            campaign.templateName || 'hello_world',
            campaign.templateLanguage || 'en_US',
            campaign.total,
            campaign.queued,
            campaign.accepted,
            campaign.sent,
            campaign.delivered,
            campaign.read,
            campaign.failed,
            campaign.excludedOptOut,
            campaign.createdAt ? new Date(campaign.createdAt) : new Date(),
            campaign.updatedAt ? new Date(campaign.updatedAt) : new Date(),
          ]
        );
      } else {
        throw err;
      }
    }

    if (campaign.messages && campaign.messages.length > 0) {
      for (const msg of campaign.messages) {
        await messageStore.upsert(effectiveBizId ? { ...msg, businessId: effectiveBizId } : msg);
      }
    }

    return campaign;
  }

  public async updateStatus(campaignId: string, status: CampaignStatus): Promise<StoredCampaign | undefined> {
    const pool = getPool();
    await pool.query(
      `UPDATE campaigns
       SET status = $2, updated_at = NOW()
       WHERE campaign_id = $1;`,
      [campaignId, status]
    );

    return this.get(campaignId);
  }

  public async clear(): Promise<void> {
    const pool = getPool();
    await pool.query('DELETE FROM recipient_reservations;');
    await pool.query('DELETE FROM campaign_messages;');
    await pool.query('DELETE FROM campaigns;');
  }
}

export const campaignStore = new CampaignStore();
