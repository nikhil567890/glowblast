import { getPool } from '../db/pool';
import { StoredCampaign, CampaignSummary, CampaignStatus } from '../types/campaign';
import { messageStore } from './messageStore';

export class CampaignStore {
  public async get(campaignId: string): Promise<StoredCampaign | undefined> {
    const pool = getPool();
    const res = await pool.query<{
      campaign_id: string;
      client_request_token: string | null;
      campaign_name: string;
      status: string;
      template_name: string;
      template_language: string;
      total_recipients: number;
      count_queued: number;
      count_accepted: number;
      count_sent: number;
      count_delivered: number;
      count_read: number;
      count_failed: number;
      count_excluded_opt_out: number;
      created_at: Date;
      updated_at: Date;
    }>(
      `SELECT campaign_id, client_request_token, campaign_name, status, template_name, template_language,
              total_recipients, count_queued, count_accepted, count_sent, count_delivered,
              count_read, count_failed, count_excluded_opt_out, created_at, updated_at
       FROM campaigns
       WHERE campaign_id = $1
       LIMIT 1;`,
      [campaignId]
    );

    if (res.rows.length === 0) return undefined;
    const row = res.rows[0];

    const messages = await messageStore.getByCampaignId(campaignId);

    return {
      campaignId: row.campaign_id,
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
      failed: row.count_failed,
      excludedOptOut: row.count_excluded_opt_out,
      messages,
      createdAt: row.created_at.toISOString(),
      updatedAt: row.updated_at.toISOString(),
    };
  }

  public async getByClientRequestToken(token: string): Promise<StoredCampaign | undefined> {
    const pool = getPool();
    const res = await pool.query<{ campaign_id: string }>(
      `SELECT campaign_id FROM campaigns WHERE client_request_token = $1 LIMIT 1;`,
      [token]
    );
    if (res.rows.length === 0) return undefined;
    return this.get(res.rows[0].campaign_id);
  }

  public async getSummary(campaignId: string): Promise<CampaignSummary | undefined> {
    const camp = await this.get(campaignId);
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
    const failed = msgs.filter((m) => ['failed', 'uncertain_timeout'].includes(m.status)).length;
    const excludedOptOut = msgs.filter((m) => m.status === 'excluded_opt_out').length;

    return {
      campaignId: camp.campaignId,
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
      failed,
      excludedOptOut,
      createdAt: camp.createdAt,
      updatedAt: camp.updatedAt,
    };
  }

  public async calculateCampaignStatus(campaignId: string): Promise<CampaignStatus> {
    const camp = await this.get(campaignId);
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

  public async recalculateAndSaveCampaignStatus(campaignId: string): Promise<CampaignSummary | undefined> {
    const summary = await this.getSummary(campaignId);
    if (!summary) return undefined;

    const newStatus = await this.calculateCampaignStatus(campaignId);
    const pool = getPool();

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

    return {
      ...summary,
      status: newStatus,
      updatedAt: new Date().toISOString(),
    };
  }

  public async create(campaign: StoredCampaign): Promise<StoredCampaign> {
    const pool = getPool();
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

    if (campaign.messages && campaign.messages.length > 0) {
      for (const msg of campaign.messages) {
        await messageStore.upsert(msg);
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
