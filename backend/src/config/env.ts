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
  };
}

/**
 * Parses comma-separated authorized test recipient numbers.
 */
export function getAuthorizedTestRecipients(): string[] {
  if (!env.TEST_RECIPIENTS) return [];
  return env.TEST_RECIPIENTS.split(',')
    .map((num) => num.replace(/\D/g, '').trim())
    .filter((num) => num.length >= 10);
}
