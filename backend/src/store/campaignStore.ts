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
      total: camp.total,
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
}

export const campaignStore = new CampaignStore();
