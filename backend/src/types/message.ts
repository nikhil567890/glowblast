export type MessageStatus =
  | 'queued'
  | 'sending'
  | 'accepted'
  | 'sent'
  | 'delivered'
  | 'read'
  | 'failed'
  | 'excluded_opt_out'
  | 'uncertain_timeout';

export interface RecipientInput {
  localCustomerId: string;
  name: string;
  phone: string;
}

export interface StoredMessage {
  id: string; // Internal message ID: e.g. campaignId_localCustomerId
  campaignId: string;
  businessId?: string;
  localCustomerId: string;
  recipientName: string;
  normalizedPhone: string;
  status: MessageStatus;
  providerMessageId?: string;
  templateName?: string;
  templateLanguage?: string;
  errorCode?: number;
  errorTitle?: string;
  errorMessage?: string;
  errorDetails?: string;
  repliedAt?: string;
  createdAt: string;
  updatedAt: string;
}

