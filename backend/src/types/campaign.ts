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
  campaignId: string;
  businessName?: string;
  campaignName: string;
  templateId?: string;
  templateName: string;
  templateLanguage: string;
  templateVariables?: string[];
  templateComponents?: Array<{
    type: string;
    parameters: Array<{
      type: string;
      text?: string;
      [key: string]: any;
    }>;
  }>;
  recipients: Array<{
    localCustomerId: string;
    name: string;
    phone: string;
  }>;
  optedOutPhones?: string[];
  metadata?: Record<string, any>;
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

