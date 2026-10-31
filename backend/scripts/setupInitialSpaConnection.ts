/**
 * GlowBlast - Operator Setup Script for Initial Spa WABA Connection
 *
 * Associates the verified WABA credentials with the initial spa business (a0000000-0000-4000-8000-000000000001).
 *
 * Requirements:
 * - Uses backend AES-256-GCM encryption with tenant-bound AAD.
 * - Never prints raw tokens to logs/stdout.
 * - Supports --dry-run and mode selection (--mode=test | --mode=production).
 * - Safe and idempotent: can be run repeatedly without duplicating active connections.
 *
 * Usage:
 *   npx tsx scripts/setupInitialSpaConnection.ts [--mode=test|production] [--dry-run]
 */

import { env } from '../src/config/env';
import { INITIAL_BUSINESS_ID } from '../src/middleware/authMiddleware';
import { wabaConnectionStore } from '../src/store/wabaConnectionStore';
import { encryptWabaToken, decryptWabaToken } from '../src/utils/tokenEncryption';

export interface InitialSpaCredentials {
  businessId: string;
  wabaId: string;
  phoneNumberId: string;
  rawToken: string;
  displayNumber: string;
  mode: 'test' | 'production';
}

/**
 * Resolves source credentials and configured display numbers from environment.
 * Uses canonical configured names: PROD_WHATSAPP_DISPLAY_NUMBER and TEST_WHATSAPP_DISPLAY_NUMBER.
 */
export function resolveInitialSpaCredentials(
  mode: 'test' | 'production',
  envConfig: typeof env = env
): InitialSpaCredentials {
  let wabaId: string | undefined;
  let phoneNumberId: string | undefined;
  let rawToken: string | undefined;
  let displayNumber: string | undefined;

  if (mode === 'production') {
    wabaId = envConfig.PROD_WHATSAPP_BUSINESS_ACCOUNT_ID || envConfig.WHATSAPP_BUSINESS_ACCOUNT_ID;
    phoneNumberId = envConfig.PROD_WHATSAPP_PHONE_NUMBER_ID || envConfig.WHATSAPP_PHONE_NUMBER_ID;
    rawToken = envConfig.PROD_WHATSAPP_ACCESS_TOKEN || envConfig.WHATSAPP_ACCESS_TOKEN;
    displayNumber = envConfig.PROD_WHATSAPP_DISPLAY_NUMBER || '+919502259203';
  } else {
    wabaId = (envConfig as any).TEST_WHATSAPP_BUSINESS_ACCOUNT_ID || envConfig.WHATSAPP_BUSINESS_ACCOUNT_ID;
    phoneNumberId = (envConfig as any).TEST_WHATSAPP_PHONE_NUMBER_ID || envConfig.WHATSAPP_PHONE_NUMBER_ID;
    rawToken = (envConfig as any).TEST_WHATSAPP_ACCESS_TOKEN || envConfig.WHATSAPP_ACCESS_TOKEN;
    displayNumber = envConfig.TEST_WHATSAPP_DISPLAY_NUMBER || '+1 (555) 632-5494';
  }

  if (!wabaId || !phoneNumberId || !rawToken) {
    throw new Error(`Incomplete credentials for mode '${mode}'. Required: WABA ID, Phone Number ID, Access Token.`);
  }

  return {
    businessId: INITIAL_BUSINESS_ID,
    wabaId,
    phoneNumberId,
    rawToken,
    displayNumber,
    mode,
  };
}

export interface SetupOptions {
  mode: 'test' | 'production';
  isDryRun: boolean;
}

export async function executeInitialSpaSetup(options: SetupOptions) {
  const { mode, isDryRun } = options;
  console.log(`[OperatorSetup] Initializing WABA setup for initial spa (${INITIAL_BUSINESS_ID})...`);
  console.log(`[OperatorSetup] Mode: ${mode} | Dry-run: ${isDryRun}`);

  const creds = resolveInitialSpaCredentials(mode);

  // Verify encryption subsystem
  console.log('[OperatorSetup] Testing AES-256-GCM encryption with tenant-bound AAD...');
  const encrypted = encryptWabaToken(creds.rawToken, { aad: INITIAL_BUSINESS_ID });
  const decrypted = decryptWabaToken(encrypted, { aad: INITIAL_BUSINESS_ID });

  if (decrypted !== creds.rawToken) {
    throw new Error('Fatal: Encryption round-trip verification failed!');
  }
  console.log('[OperatorSetup] Encryption verified successfully. Ciphertext generated with unique 96-bit IV.');

  if (isDryRun) {
    console.log('[OperatorSetup] [DRY RUN] Would save connection record:');
    const dryRunSummary = {
      businessId: INITIAL_BUSINESS_ID,
      wabaId: creds.wabaId,
      phoneNumberId: creds.phoneNumberId,
      displayNumber: creds.displayNumber,
      mode,
      keyId: encrypted.keyId,
      ivLengthHex: encrypted.tokenIv.length,
      tagLengthHex: encrypted.tokenTag.length,
    };
    console.log(dryRunSummary);
    console.log('[OperatorSetup] Dry run completed successfully without writing to database.');
    return { dryRun: true, summary: dryRunSummary };
  }

  console.log('[OperatorSetup] Persisting encrypted connection record to database...');
  const saved = await wabaConnectionStore.saveConnection({
    businessId: INITIAL_BUSINESS_ID,
    wabaId: creds.wabaId,
    phoneNumberId: creds.phoneNumberId,
    displayNumber: creds.displayNumber,
    mode,
    plainAccessToken: creds.rawToken,
    verifiedName: 'GlowBlast Initial Spa',
    metaAppId: (env as any).META_APP_ID || undefined,
  });

  console.log(`[OperatorSetup] Successfully saved connection ID: ${saved.id}`);

  // Verification read
  const active = await wabaConnectionStore.getActiveConnection(INITIAL_BUSINESS_ID, mode);
  if (!active || active.phoneNumberId !== creds.phoneNumberId) {
    throw new Error('Saved connection could not be retrieved as active connection.');
  }

  console.log(`[OperatorSetup] Verified active connection for business ${INITIAL_BUSINESS_ID}:`);
  console.log(`  - Connection ID: ${active.id}`);
  console.log(`  - WABA ID: ${active.wabaId}`);
  console.log(`  - Phone Number ID: ${active.phoneNumberId}`);
  console.log(`  - Display Number: ${active.displayNumber}`);
  console.log(`  - Mode: ${active.mode}`);
  console.log(`  - Key ID: ${active.keyId}`);
  console.log(`  - Created At: ${active.createdAt}`);
  console.log('[OperatorSetup] Done.');

  return { dryRun: false, connection: active };
}

async function run() {
  const args = process.argv.slice(2);
  const isDryRun = args.includes('--dry-run');
  const modeArg = args.find((a) => a.startsWith('--mode='));
  const mode: 'test' | 'production' = modeArg ? (modeArg.split('=')[1] as any) : 'test';

  await executeInitialSpaSetup({ mode, isDryRun });
}

if (require.main === module) {
  run().catch((err) => {
    console.error('[OperatorSetup] Unhandled error:', err.message);
    process.exit(1);
  });
}
