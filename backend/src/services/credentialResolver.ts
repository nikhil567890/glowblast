import { env } from '../config/env';
import { INITIAL_BUSINESS_ID } from '../middleware/authMiddleware';
import { wabaConnectionStore } from '../store/wabaConnectionStore';
import { decryptWabaToken } from '../utils/tokenEncryption';
import { WabaConnectionMode } from '../types/wabaConnection';

export interface ResolvedWhatsAppCredentials {
  businessId: string;
  wabaId: string;
  phoneNumberId: string;
  accessToken: string;
  displayNumber?: string;
  mode: WabaConnectionMode;
  source: 'business_connection' | 'initial_spa_legacy_fallback';
}

export class CredentialResolutionError extends Error {
  public readonly code: string;
  public readonly httpStatus: number;

  constructor(code: string, message: string, httpStatus: number = 403) {
    super(message);
    this.name = 'CredentialResolutionError';
    this.code = code;
    this.httpStatus = httpStatus;
  }
}

/**
 * Resolves verified WhatsApp Business Account (WABA) credentials for an authenticated business.
 *
 * Security Guarantees:
 * 1. Authority: Uses ONLY the verified database connection belonging to target businessId.
 *    Client-supplied credentials (tokens, WABA IDs, phone IDs) are NEVER accepted as authority.
 * 2. Authenticated Decryption: Encrypted tokens are decrypted on-demand via AES-256-GCM.
 * 3. Strict Tenant Isolation: Never falls back to another business's connection.
 * 4. Controlled Compatibility Fallback:
 *    ONLY the explicitly verified initial business ('a0000000-0000-4000-8000-000000000001')
 *    is permitted to use global environment variables if no dedicated database connection is provisioned.
 *    NO OTHER BUSINESS CAN EVER INHERIT THIS FALLBACK.
 * 5. Fail-Closed: If no authorized connection exists, throws WHATSAPP_CONNECTION_NOT_CONFIGURED.
 */
export async function resolveBusinessWhatsAppCredentials(
  businessId: string,
  mode: WabaConnectionMode = 'test',
  options?: { customEncryptionKey?: string }
): Promise<ResolvedWhatsAppCredentials> {
  if (!businessId || typeof businessId !== 'string' || businessId.trim().length === 0) {
    throw new CredentialResolutionError(
      'UNAUTHORIZED_BUSINESS_CONTEXT',
      'A valid verified business ID is required to resolve WhatsApp credentials.',
      401
    );
  }

  const cleanBizId = businessId.trim();

  // 1. Look for an active, encrypted WABA connection provisioned in PostgreSQL for this business
  const storedConn = await wabaConnectionStore.getActiveConnection(cleanBizId, mode);

  if (storedConn && storedConn.isActive) {
    try {
      // Decrypt token with tenant-bound AAD verification (AAD = cleanBizId)
      const decryptedToken = decryptWabaToken(
        {
          encryptedAccessToken: storedConn.encryptedAccessToken,
          tokenIv: storedConn.tokenIv,
          tokenTag: storedConn.tokenTag,
          keyId: storedConn.keyId,
        },
        {
          customKey: options?.customEncryptionKey,
          aad: cleanBizId,
        }
      );

      return {
        businessId: cleanBizId,
        wabaId: storedConn.wabaId,
        phoneNumberId: storedConn.phoneNumberId,
        accessToken: decryptedToken,
        displayNumber: storedConn.displayNumber,
        mode,
        source: 'business_connection',
      };
    } catch (decryptErr: any) {
      console.error(
        `[CredentialResolver] Token decryption failed for business ${cleanBizId}: ${decryptErr.message}`
      );
      throw new CredentialResolutionError(
        'WABA_TOKEN_DECRYPTION_FAILED',
        'Failed to decrypt stored WhatsApp credentials. Encryption key mismatch or corrupted cipher material.',
        500
      );
    }
  }

  // 2. Controlled Legacy Compatibility Fallback: STRICTLY for INITIAL_BUSINESS_ID only
  if (cleanBizId === INITIAL_BUSINESS_ID) {
    const isProd = mode === 'production';
    const legacyPhoneId = isProd
      ? env.PROD_WHATSAPP_PHONE_NUMBER_ID
      : env.WHATSAPP_PHONE_NUMBER_ID;
    const legacyWabaId = isProd
      ? env.PROD_WHATSAPP_BUSINESS_ACCOUNT_ID
      : env.WHATSAPP_BUSINESS_ACCOUNT_ID;
    const legacyToken = isProd
      ? env.PROD_WHATSAPP_ACCESS_TOKEN
      : env.WHATSAPP_ACCESS_TOKEN;
    const legacyDisplay = isProd
      ? env.PROD_WHATSAPP_DISPLAY_NUMBER
      : env.TEST_WHATSAPP_DISPLAY_NUMBER;

    if (legacyPhoneId && legacyToken && legacyWabaId) {
      return {
        businessId: INITIAL_BUSINESS_ID,
        wabaId: legacyWabaId,
        phoneNumberId: legacyPhoneId,
        accessToken: legacyToken,
        displayNumber: legacyDisplay,
        mode,
        source: 'initial_spa_legacy_fallback',
      };
    }
  }

  // 3. Fail closed: Business has no authorized WhatsApp Cloud API connection
  throw new CredentialResolutionError(
    'WHATSAPP_CONNECTION_NOT_CONFIGURED',
    'WhatsApp Cloud API connection is not configured for this business. Please connect your verified WhatsApp Business Account.',
    403
  );
}
