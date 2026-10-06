import dotenv from 'dotenv';
import { z } from 'zod';

dotenv.config();

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  PORT: z.string().default('3000').transform((val) => parseInt(val, 10)),
  WHATSAPP_API_VERSION: z.string().default('v22.0'),
  WHATSAPP_PHONE_NUMBER_ID: z.string().default('1272717865934207'),
  WHATSAPP_BUSINESS_ACCOUNT_ID: z.string().default('1633948435034571'),
  TEST_WHATSAPP_DISPLAY_NUMBER: z.string().default('+1 (555) 632-5494'),
  WHATSAPP_ACCESS_TOKEN: z.string().default(''),
  META_VERIFY_TOKEN: z.string().default('glowblast_webhook_verify_token'),
  CORS_ALLOWED_ORIGINS: z.string().default('*'),
  BACKEND_BASE_URL: z.string().default('http://localhost:3000'),
  TEST_RECIPIENT_LIMIT: z.string().default('5').transform((val) => parseInt(val, 10)),
  TEST_CAMPAIGN_ENABLED: z.string().default('true').transform((val) => val === 'true'),
  TEST_RECIPIENTS: z.string().default(''),
  BREVO_API_KEY: z.string().default(''),
  BREVO_SENDER_EMAIL: z.string().default(''),
  BREVO_SENDER_NAME: z.string().default('GlowBlast'),
  JWT_SECRET: z.string().default('glowblast_jwt_super_secret_dev_2026'),
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  console.error('[Config] Invalid environment variables:', parsed.error.format());
  throw new Error('Environment configuration validation failed');
}

export const env = parsed.data;

/**
 * Returns safe status information without exposing secret tokens.
 */
export function getSafeConfigStatus() {
  return {
    configured: !!(env.WHATSAPP_PHONE_NUMBER_ID && env.WHATSAPP_ACCESS_TOKEN),
    phoneNumberIdConfigured: !!env.WHATSAPP_PHONE_NUMBER_ID,
    tokenConfigured: !!env.WHATSAPP_ACCESS_TOKEN,
    testMode: true,
    testRecipientLimit: env.TEST_RECIPIENT_LIMIT,
    displayNumber: env.TEST_WHATSAPP_DISPLAY_NUMBER,
    apiVersion: env.WHATSAPP_API_VERSION,
    brevoConfigured: !!(env.BREVO_API_KEY && env.BREVO_SENDER_EMAIL),
  };
}

/**
 * Returns safe Brevo configuration status without exposing API key.
 */
export function getSafeBrevoStatus() {
  return {
    configured: !!(env.BREVO_API_KEY && env.BREVO_SENDER_EMAIL),
    senderEmailConfigured: !!env.BREVO_SENDER_EMAIL,
    senderName: env.BREVO_SENDER_NAME,
  };
}

import { normalizeWhatsAppPhone } from '../utils/phone';

/**
 * Parses comma-separated authorized test recipient numbers using the central
 * normalization function.
 */
export function getAuthorizedTestRecipients(): string[] {
  if (!env.TEST_RECIPIENTS) return [];
  return env.TEST_RECIPIENTS.split(',')
    .map((num) => normalizeWhatsAppPhone(num.trim()))
    .filter((num): num is string => !!num);
}

