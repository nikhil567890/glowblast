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
  clientRequestToken?: string | null;
  campaignId?: string | null;
  businessName?: string | null;
  campaignName: string;
  mode?: 'demo' | 'test' | 'production' | null;
  userEmail?: string | null;
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
    hasConsent?: boolean | null;
    consentRecordedAt?: string | null;
  }>;
  optedOutPhones?: string[] | null;
  metadata?: Record<string, any> | null;
}

export interface CampaignSummary {
  campaignId: string;
  clientRequestToken?: string;
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
  replied?: number;
  failed: number;
  excludedOptOut: number;
  createdAt: string;
  updatedAt: string;
}

export interface StoredCampaign extends CampaignSummary {
  messages: StoredMessage[];
}

