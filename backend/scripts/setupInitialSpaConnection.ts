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

async function run() {
  const args = process.argv.slice(2);
  const isDryRun = args.includes('--dry-run');
  const modeArg = args.find((a) => a.startsWith('--mode='));
  const mode: 'test' | 'production' = modeArg ? (modeArg.split('=')[1] as any) : 'test';

  console.log(`[OperatorSetup] Initializing WABA setup for initial spa (${INITIAL_BUSINESS_ID})...`);
  console.log(`[OperatorSetup] Mode: ${mode} | Dry-run: ${isDryRun}`);

  // Resolve source credentials from environment
  let wabaId: string | undefined;
  let phoneNumberId: string | undefined;
  let rawToken: string | undefined;
  let displayNumber: string | undefined;

  if (mode === 'production') {
    wabaId = env.PROD_WHATSAPP_BUSINESS_ACCOUNT_ID || env.WHATSAPP_BUSINESS_ACCOUNT_ID;
    phoneNumberId = env.PROD_WHATSAPP_PHONE_NUMBER_ID || env.WHATSAPP_PHONE_NUMBER_ID;
    rawToken = env.PROD_WHATSAPP_ACCESS_TOKEN || env.WHATSAPP_ACCESS_TOKEN;
    displayNumber = env.PROD_WHATSAPP_DISPLAY_PHONE_NUMBER || '+1 (555) 000-0000';
  } else {
    wabaId = env.TEST_WHATSAPP_BUSINESS_ACCOUNT_ID || env.WHATSAPP_BUSINESS_ACCOUNT_ID;
    phoneNumberId = env.TEST_WHATSAPP_PHONE_NUMBER_ID || env.WHATSAPP_PHONE_NUMBER_ID;
    rawToken = env.TEST_WHATSAPP_ACCESS_TOKEN || env.WHATSAPP_ACCESS_TOKEN;
    displayNumber = env.TEST_WHATSAPP_DISPLAY_PHONE_NUMBER || '+1 (555) 019-2834';
  }

  if (!wabaId || !phoneNumberId || !rawToken) {
    console.error(`[OperatorSetup] Error: Incomplete credentials for mode '${mode}'.`);
    console.error(`  WABA ID: ${wabaId ? 'configured' : 'MISSING'}`);
    console.error(`  Phone Number ID: ${phoneNumberId ? 'configured' : 'MISSING'}`);
    console.error(`  Access Token: ${rawToken ? 'configured' : 'MISSING'}`);
    process.exit(1);
  }

  // Verify encryption subsystem
  console.log('[OperatorSetup] Testing AES-256-GCM encryption with tenant-bound AAD...');
  const encrypted = encryptWabaToken(rawToken, { aad: INITIAL_BUSINESS_ID });
  const decrypted = decryptWabaToken(encrypted, { aad: INITIAL_BUSINESS_ID });

  if (decrypted !== rawToken) {
    console.error('[OperatorSetup] Fatal: Encryption round-trip verification failed!');
    process.exit(1);
  }
  console.log('[OperatorSetup] Encryption verified successfully. Ciphertext generated with unique 96-bit IV.');

  if (isDryRun) {
    console.log('[OperatorSetup] [DRY RUN] Would save connection record:');
    console.log({
      businessId: INITIAL_BUSINESS_ID,
      wabaId,
      phoneNumberId,
      displayNumber,
      mode,
      keyId: encrypted.keyId,
      ivLengthHex: encrypted.tokenIv.length,
      tagLengthHex: encrypted.tokenTag.length,
    });
    console.log('[OperatorSetup] Dry run completed successfully without writing to database.');
    return;
  }

  console.log('[OperatorSetup] Persisting encrypted connection record to database...');
  const saved = await wabaConnectionStore.saveConnection({
    businessId: INITIAL_BUSINESS_ID,
    wabaId,
    phoneNumberId,
    displayNumber,
    mode,
    plainAccessToken: rawToken,
    verifiedName: 'GlowBlast Initial Spa',
    metaAppId: env.META_APP_ID || undefined,
  });

  console.log(`[OperatorSetup] Successfully saved connection ID: ${saved.id}`);

  // Verification read
  const active = await wabaConnectionStore.getActiveConnection(INITIAL_BUSINESS_ID, mode);
  if (!active || active.phoneNumberId !== phoneNumberId) {
    console.error('[OperatorSetup] Error: Saved connection could not be retrieved as active connection.');
    process.exit(1);
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
}

if (require.main === module) {
  run().catch((err) => {
    console.error('[OperatorSetup] Unhandled error:', err.message);
    process.exit(1);
  });
}
