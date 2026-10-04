import { z } from 'zod';
import { env } from '../config/env';

export const singleMessageSchema = z.object({
  phone: z.string().min(10, 'Valid phone number is required'),
  name: z.string().optional(),
  templateName: z.string().default('hello_world'),
  templateLanguage: z.string().default('en_US'),
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
  templateName: z.string().default('hello_world'),
  templateLanguage: z.string().default('en_US'),
  recipients: z.array(recipientSchema).min(1, 'At least one recipient is required'),
  optedOutPhones: z.array(z.string()).optional(),
});
