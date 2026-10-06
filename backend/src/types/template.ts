export type TemplateCategory = 'MARKETING' | 'UTILITY' | 'AUTHENTICATION';

export type TemplateApprovalStatus =
  | 'draft'
  | 'pending_approval'
  | 'approved'
  | 'rejected'
  | 'disabled';

export type MetaTemplateStatus =
  | 'APPROVED'
  | 'PENDING'
  | 'REJECTED'
  | 'PAUSED'
  | 'DISABLED'
  | 'NOT_SUBMITTED';

export interface WhatsAppTemplate {
  id: string; // GlowBlast internal ID: e.g. 'tpl_birthday', 'tpl_hello_world'
  name: string; // Meta template name: alphanumeric lowercase + underscores, e.g. 'birthday_offer'
  displayName: string; // Friendly name: e.g. 'Birthday Pampering'
  description?: string;
  category: TemplateCategory;
  language: string; // e.g. 'en_US'
  status: TemplateApprovalStatus;
  metaStatus: MetaTemplateStatus;
  metaTemplateId?: string;
  body: string; // Text containing variables like {name}, {business_name}
  variables: string[]; // ['name', 'business_name']
  exampleValues?: Record<string, string>;
  createdAt: string;
  updatedAt: string;
  lastSyncedAt?: string;
}

export interface CreateTemplateInput {
  name: string;
  displayName: string;
  description?: string;
  category: TemplateCategory;
  language?: string;
  body: string;
  variables?: string[];
  exampleValues?: Record<string, string>;
  submitToMeta?: boolean;
}
