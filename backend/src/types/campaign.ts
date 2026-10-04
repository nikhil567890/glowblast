import { StoredMessage } from './message';

export type CampaignStatus = 'pending' | 'processing' | 'completed' | 'failed';

export interface CampaignSendRequest {
  campaignId: string;
  businessName?: string;
  campaignName: string;
  templateName?: string;
  templateLanguage?: string;
  recipients: Array<{
    localCustomerId: string;
    name: string;
    phone: string;
  }>;
  optedOutPhones?: string[];
}

export interface CampaignSummary {
  campaignId: string;
  campaignName: string;
  status: CampaignStatus;
  total: number;
  accepted: number;
  sent: number;
  delivered: number;
  read: number;
  failed: number;
  excludedOptOut: number;
  createdAt: string;
  updatedAt: string;
}

export interface StoredCampaign extends CampaignSummary {
  messages: StoredMessage[];
}
