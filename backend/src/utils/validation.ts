import { z } from 'zod';
import { env } from '../config/env';

export const templateComponentSchema = z.object({
  type: z.string(),
  parameters: z.array(
    z.object({
      type: z.string(),
      text: z.string().optional(),
    }).passthrough()
  ),
});

export const singleMessageSchema = z.object({
  phone: z.string().min(10, 'Valid phone number is required'),
  name: z.string().optional(),
  templateId: z.string().optional(),
  templateName: z.string().min(1, 'templateName is required'),
  templateLanguage: z.string().default('en_US'),
  templateVariables: z.array(z.string()).optional(),
  templateComponents: z.array(templateComponentSchema).optional(),
});

export const recipientSchema = z.object({
  localCustomerId: z.string().min(1, 'localCustomerId is required'),
  name: z.string().min(1, 'Customer name is required'),
  phone: z.string().min(10, 'Valid phone number is required'),
});

export const campaignSendSchema = z.object({
  campaignId: z.string().min(1, 'campaignId is required'),
  businessName: z.string().optional(),
  campaignName: z.string().min(1, 'campaignName is required'),
  templateId: z.string().optional(),
  templateName: z.string().min(1, 'templateName is required'),
  templateLanguage: z.string().min(2, 'templateLanguage is required').default('en_US'),
  templateVariables: z.array(z.string()).optional(),
  templateComponents: z.array(templateComponentSchema).optional(),
  recipients: z.array(recipientSchema).min(1, 'At least one recipient is required'),
  optedOutPhones: z.array(z.string()).optional(),
  metadata: z.record(z.any()).optional(),
});

