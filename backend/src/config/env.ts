import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';
import { z } from 'zod';

// Load local environment files:
// 1. .env.local takes precedence for local developer overrides (e.g. TEST_DATABASE_URL)
// 2. .env provides base local configuration
const candidateDirs = [
  process.cwd(),
  path.join(process.cwd(), 'backend'),
  path.resolve(__dirname, '../..'),
];

for (const dir of candidateDirs) {
  const envLocalPath = path.join(dir, '.env.local');
  if (fs.existsSync(envLocalPath)) {
    dotenv.config({ path: envLocalPath });
    break;
  }
}

for (const dir of candidateDirs) {
  const envPath = path.join(dir, '.env');
  if (fs.existsSync(envPath)) {
    dotenv.config({ path: envPath });
    break;
  }
}

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
  WHATSAPP_WEBHOOK_VERIFY_TOKEN: z.string().optional(),
  CORS_ALLOWED_ORIGINS: z.string().default('*'),
  BACKEND_BASE_URL: z.string().default('http://localhost:3000'),
  TEST_RECIPIENT_LIMIT: z.string().default('5').transform((val) => parseInt(val, 10)),
  TEST_CAMPAIGN_ENABLED: z.string().default('true').transform((val) => val === 'true'),
  TEST_RECIPIENTS: z.string().default(''),
  // Production Meta WhatsApp Account Configuration
  PROD_WHATSAPP_PHONE_NUMBER_ID: z.string().default('1436324276220624'),
  PROD_WHATSAPP_BUSINESS_ACCOUNT_ID: z.string().default('3226959717495309'),
  PROD_WHATSAPP_DISPLAY_NUMBER: z.string().default('+919502259203'),
  PROD_WHATSAPP_ACCESS_TOKEN: z.string().default(''),
  // Production Safety Controls
  ENABLE_PRODUCTION_CAMPAIGNS: z.string().default('false').transform((val) => val === 'true'),
  PRODUCTION_ALLOWED_EMAILS: z.string().default(''),
  PROD_UNIQUE_RECIPIENTS_PER_24H_LIMIT: z.string().default('200').transform((val) => parseInt(val, 10)),
  BREVO_API_KEY: z.string().default(''),
  BREVO_SENDER_EMAIL: z.string().default(''),
  BREVO_SENDER_NAME: z.string().default('GlowBlast'),
  JWT_SECRET: z.string().default('glowblast_jwt_super_secret_dev_2026'),
  OTP_HMAC_SECRET: z.string().default('glowblast_otp_hmac_secret_dev_2026'),
  // AES-256-GCM encryption key for multi-business WABA tokens (32 bytes = 64 hex chars or 44 base64 chars)
  // Canonical: WABA_TOKEN_ENCRYPTION_KEY, with seamless fallback alias: WABA_ENCRYPTION_KEY
  WABA_TOKEN_ENCRYPTION_KEY: z.string().optional(),
  WABA_ENCRYPTION_KEY: z.string().optional(),
  META_APP_SECRET: z.string().optional(),
  // Neon PostgreSQL Database Configuration
  DATABASE_URL: z.string().optional(),
  TEST_DATABASE_URL: z.string().optional(),
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
  const isTestConfigured = !!(env.WHATSAPP_PHONE_NUMBER_ID && env.WHATSAPP_ACCESS_TOKEN);
  const isProdConfigured = !!(
    env.PROD_WHATSAPP_PHONE_NUMBER_ID &&
    env.PROD_WHATSAPP_BUSINESS_ACCOUNT_ID &&
    env.PROD_WHATSAPP_ACCESS_TOKEN
  );

  return {
    configured: isTestConfigured,
    phoneNumberIdConfigured: !!env.WHATSAPP_PHONE_NUMBER_ID,
    tokenConfigured: !!env.WHATSAPP_ACCESS_TOKEN,
    testMode: true,
    testRecipientLimit: env.TEST_RECIPIENT_LIMIT,
    displayNumber: env.TEST_WHATSAPP_DISPLAY_NUMBER,
    apiVersion: env.WHATSAPP_API_VERSION,
    brevoConfigured: !!(env.BREVO_API_KEY && env.BREVO_SENDER_EMAIL),
    wabaEncryptionConfigured: !!(env.WABA_TOKEN_ENCRYPTION_KEY || env.WABA_ENCRYPTION_KEY),
    database: getSafeDatabaseStatus(),
    modes: {
      demo: {
        available: true,
      },
      test: {
        configured: isTestConfigured,
        displayNumber: env.TEST_WHATSAPP_DISPLAY_NUMBER,
        recipientLimit: env.TEST_RECIPIENT_LIMIT,
        phoneNumberId: env.WHATSAPP_PHONE_NUMBER_ID,
      },
      production: {
        enabled: env.ENABLE_PRODUCTION_CAMPAIGNS,
        configured: isProdConfigured,
        displayNumber: env.PROD_WHATSAPP_DISPLAY_NUMBER,
        phoneNumberId: env.PROD_WHATSAPP_PHONE_NUMBER_ID,
        businessAccountId: env.PROD_WHATSAPP_BUSINESS_ACCOUNT_ID,
        dailyUniqueLimit: env.PROD_UNIQUE_RECIPIENTS_PER_24H_LIMIT,
        allowedEmailsConfigured: !!env.PRODUCTION_ALLOWED_EMAILS,
      },
    },
  };
}

/**
 * Resolves the active database URL based on environment context.
 * - In production mode, strictly requires DATABASE_URL configured in Render. TEST_DATABASE_URL is NEVER used in production.
 * - In development or test mode, reads TEST_DATABASE_URL (or falls back to DATABASE_URL if in local dev).
 *
 * NOTE: For strict security, this value must NEVER be logged, displayed, or sent to clients.
 */
export function getActiveDatabaseUrl(): string | undefined {
  if (env.NODE_ENV === 'production') {
    return env.DATABASE_URL;
  }
  return env.TEST_DATABASE_URL || env.DATABASE_URL;
}

/**
 * Returns safe database configuration status without exposing credentials or connection strings.
 */
export function getSafeDatabaseStatus() {
  const isProd = env.NODE_ENV === 'production';
  const hasUrl = !!(isProd ? env.DATABASE_URL : (env.TEST_DATABASE_URL || env.DATABASE_URL));
  return {
    configured: hasUrl,
    mode: isProd ? 'production' : 'test/dev',
    sourceVariable: isProd
      ? (env.DATABASE_URL ? 'DATABASE_URL' : 'none')
      : (env.TEST_DATABASE_URL ? 'TEST_DATABASE_URL' : env.DATABASE_URL ? 'DATABASE_URL' : 'none'),
  };
}

/**
 * Checks if production credentials are fully present.
 */
export function isProductionConfigured(): boolean {
  return !!(
    env.PROD_WHATSAPP_PHONE_NUMBER_ID &&
    env.PROD_WHATSAPP_BUSINESS_ACCOUNT_ID &&
    env.PROD_WHATSAPP_ACCESS_TOKEN
  );
}

/**
 * Returns parsed list of lowercase authorized email addresses for production campaigns.
 */
export function getProductionAllowedEmails(): string[] {
  if (!env.PRODUCTION_ALLOWED_EMAILS) return [];
  return env.PRODUCTION_ALLOWED_EMAILS.split(',')
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
}

/**
 * Verifies if a given email is authorized for production sending.
 */
export function isEmailAuthorizedForProduction(email?: string): boolean {
  if (!email) return false;
  const allowed = getProductionAllowedEmails();
  if (allowed.length === 0) return false; // Fail closed if no emails specified
  return allowed.includes(email.trim().toLowerCase());
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

/**
 * Resolves the webhook verification token, accepting either WHATSAPP_WEBHOOK_VERIFY_TOKEN
 * or META_VERIFY_TOKEN for consistent environment configuration.
 */
export function getWebhookVerifyToken(): string {
  return (
    process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN ||
    env.WHATSAPP_WEBHOOK_VERIFY_TOKEN ||
    env.META_VERIFY_TOKEN ||
    'glowblast_webhook_verify_token'
  );
}

