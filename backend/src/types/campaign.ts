import { StoredMessage } from './message';

export type CampaignStatus =
  | 'pending'
  | 'processing'
  | 'accepted'
  | 'completed'
  | 'completed_with_errors'
  | 'failed'
  | 'cancelled';

export interface CampaignSendRequest {
  campaignId?: string | null;
  businessName?: string | null;
  campaignName: string;
  templateId?: string | null;
  templateName: string;
  templateLanguage?: string | null;
  templateVariables?: string[] | null;
  templateComponents?: Array<{
    type: string;
    parameters: Array<{
      type: string;
      text?: string;
      [key: string]: any;
    }>;
  }> | null;
  recipients: Array<{
    localCustomerId?: string | null;
    name?: string | null;
    phone: string;
  }>;
  optedOutPhones?: string[] | null;
  metadata?: Record<string, any> | null;
}

export interface CampaignSummary {
  campaignId: string;
  campaignName: string;
  status: CampaignStatus;
  templateName?: string;
  templateLanguage?: string;
  total: number;
  queued: number;
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

