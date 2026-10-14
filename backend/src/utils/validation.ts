import { z } from 'zod';
import { env } from '../config/env';

export const templateComponentSchema = z.object({
  type: z.string(),
  parameters: z.array(
    z.object({
      type: z.string(),
      text: z.string().nullish(),
    }).passthrough()
  ),
});

export const singleMessageSchema = z.object({
  phone: z.string().min(10, 'Valid phone number is required'),
  name: z.string().nullish(),
  templateId: z.string().nullish(),
  templateName: z.string().min(1, 'templateName is required'),
  templateLanguage: z.string().nullish().default('en_US'),
  templateVariables: z.array(z.string()).nullish(),
  templateComponents: z.array(templateComponentSchema).nullish(),
});

export const recipientSchema = z.object({
  localCustomerId: z.string().nullish(),
  name: z.string().nullish(),
  phone: z.string().min(10, 'Valid phone number is required'),
  hasConsent: z.boolean().nullish(),
  consentRecordedAt: z.string().nullish(),
});

export const campaignSendSchema = z.object({
  clientRequestToken: z.string().nullish(),
  campaignId: z.string().nullish(),
  businessName: z.string().nullish(),
  campaignName: z.string().min(1, 'campaignName is required'),
  mode: z.enum(['demo', 'test', 'production']).nullish().default('test'),
  templateId: z.string().nullish(),
  templateName: z.string().min(1, 'templateName is required'),
  templateLanguage: z.string().nullish().default('en_US'),
  templateVariables: z.array(z.string()).nullish(),
  templateComponents: z.array(templateComponentSchema).nullish(),
  recipients: z.array(recipientSchema).min(1, 'At least one recipient is required'),
  optedOutPhones: z.array(z.string()).nullish(),
  metadata: z.record(z.any()).nullish(),
});

