import fs from 'fs';
import path from 'path';
import { StoredCampaign, CampaignSummary, CampaignStatus } from '../types/campaign';
import { messageStore } from './messageStore';

class CampaignStore {
  private campaigns = new Map<string, StoredCampaign>();
  private storageFile: string;

  constructor() {
    const dataDir = path.join(process.cwd(), 'data');
    if (!fs.existsSync(dataDir)) {
      try {
        fs.mkdirSync(dataDir, { recursive: true });
      } catch {
        // Fallback
      }
    }
    this.storageFile = path.join(dataDir, 'campaigns.json');
    this.loadFromDisk();
  }

  private loadFromDisk() {
    try {
      if (fs.existsSync(this.storageFile)) {
        const raw = fs.readFileSync(this.storageFile, 'utf8');
        const list: StoredCampaign[] = JSON.parse(raw);
        for (const camp of list) {
          this.campaigns.set(camp.campaignId, camp);
        }
      }
    } catch {
      // Ignore
    }
  }

  private saveToDisk() {
    try {
      const list = Array.from(this.campaigns.values());
      fs.writeFileSync(this.storageFile, JSON.stringify(list, null, 2), 'utf8');
    } catch {
      // Ignore
    }
  }

  public get(campaignId: string): StoredCampaign | undefined {
    const camp = this.campaigns.get(campaignId);
    if (!camp) return undefined;
    // Populate latest messages from messageStore
    camp.messages = messageStore.getByCampaignId(campaignId);
    return camp;
  }

  public getSummary(campaignId: string): CampaignSummary | undefined {
    const camp = this.get(campaignId);
    if (!camp) return undefined;

    // Recalculate summary metrics from actual messages
    const msgs = camp.messages;
    const queued = msgs.filter((m) => ['queued', 'sending'].includes(m.status)).length;
    const accepted = msgs.filter((m) =>
      ['accepted', 'sent', 'delivered', 'read'].includes(m.status)
    ).length;
    const sent = msgs.filter((m) => ['sent', 'delivered', 'read'].includes(m.status)).length;
    const delivered = msgs.filter((m) => ['delivered', 'read'].includes(m.status)).length;
    const read = msgs.filter((m) => m.status === 'read').length;
    const failed = msgs.filter((m) => m.status === 'failed').length;
    const excludedOptOut = msgs.filter((m) => m.status === 'excluded_opt_out').length;

    return {
      campaignId: camp.campaignId,
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

  /**
   * Computes the strict, authoritative campaign status based on message states.
   * - If any messages are still queued or sending: 'processing'
   * - If all messages failed (0 accepted/sent/delivered): 'failed'
   * - If some succeeded and some failed: 'completed_with_errors'
   * - If all messages succeeded: 'completed'
   */
  public calculateCampaignStatus(campaignId: string): CampaignStatus {
    const camp = this.get(campaignId);
    if (!camp) return 'failed';

    const msgs = camp.messages;
    const total = msgs.length;
    if (total === 0) return 'completed';

    const inFlight = msgs.filter((m) => ['queued', 'sending'].includes(m.status)).length;
    if (inFlight > 0) {
      return 'processing';
    }

    const failed = msgs.filter((m) => m.status === 'failed').length;
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

  /**
   * Recalculates the campaign's status and persists it to disk.
   */
  public recalculateAndSaveCampaignStatus(campaignId: string): CampaignSummary | undefined {
    const camp = this.campaigns.get(campaignId);
    if (!camp) return undefined;

    const newStatus = this.calculateCampaignStatus(campaignId);
    camp.status = newStatus;
    camp.updatedAt = new Date().toISOString();
    this.saveToDisk();
    return this.getSummary(campaignId);
  }

  public create(campaign: StoredCampaign): StoredCampaign {
    this.campaigns.set(campaign.campaignId, campaign);
    this.saveToDisk();
    return campaign;
  }

  public updateStatus(campaignId: string, status: CampaignStatus): StoredCampaign | undefined {
    const camp = this.campaigns.get(campaignId);
    if (!camp) return undefined;

    camp.status = status;
    camp.updatedAt = new Date().toISOString();
    this.saveToDisk();
    return camp;
  }

  public clear(): void {
    this.campaigns.clear();
    this.saveToDisk();
  }
}

export const campaignStore = new CampaignStore();

