import crypto from 'crypto';
import { env } from '../config/env';

export interface EncryptedTokenMaterial {
  encryptedAccessToken: string;
  tokenIv: string;
  tokenTag: string;
  keyId?: string;
}

/**
 * Validates and converts an AES-256-GCM encryption key into a 32-byte Buffer.
 * Supports:
 * - 64-character hexadecimal strings (32 bytes)
 * - 44-character base64 strings (32 bytes)
 * - Raw 32-byte UTF-8 strings
 *
 * Fails closed if the key is missing, empty, or not exactly 32 bytes (256 bits).
 */
export function resolveEncryptionKey(customKey?: string): Buffer {
  const rawKey =
    customKey !== undefined
      ? customKey
      : process.env.WABA_TOKEN_ENCRYPTION_KEY ||
        env.WABA_TOKEN_ENCRYPTION_KEY ||
        process.env.WABA_ENCRYPTION_KEY ||
        env.WABA_ENCRYPTION_KEY;

  if (!rawKey || typeof rawKey !== 'string' || rawKey.trim().length === 0) {
    throw new Error('ENCRYPTION_KEY_MISSING: Dedicated WABA_TOKEN_ENCRYPTION_KEY (or WABA_ENCRYPTION_KEY) is not configured.');
  }

  const trimmed = rawKey.trim();
  let keyBuffer: Buffer;

  // 1. If key consists entirely of hex characters, it must be exactly 64 characters (32 bytes)
  if (/^[0-9a-fA-F]+$/.test(trimmed)) {
    if (trimmed.length === 64) {
      keyBuffer = Buffer.from(trimmed, 'hex');
    } else {
      throw new Error(
        `INVALID_ENCRYPTION_KEY: Hexadecimal WABA_TOKEN_ENCRYPTION_KEY must be exactly 64 characters (32 bytes). Provided length: ${trimmed.length} characters.`
      );
    }
  } else if (/^[A-Za-z0-9+/]{42,43}={1,2}$/.test(trimmed) || (/^[A-Za-z0-9+/]{44}$/.test(trimmed) && Buffer.from(trimmed, 'base64').length === 32)) {
    // 2. Try Base64 format (44 characters -> 32 bytes)
    keyBuffer = Buffer.from(trimmed, 'base64');
  } else if (Buffer.byteLength(trimmed, 'utf8') === 32) {
    // 3. Raw 32-character UTF-8 string
    keyBuffer = Buffer.from(trimmed, 'utf8');
  } else {
    throw new Error(
      `INVALID_ENCRYPTION_KEY: WABA_TOKEN_ENCRYPTION_KEY must be exactly 32 bytes (64 hex characters or 32-byte base64/utf8 string). Provided length: ${Buffer.byteLength(trimmed, 'utf8')} bytes.`
    );
  }

  if (keyBuffer.length !== 32) {
    throw new Error(
      `INVALID_ENCRYPTION_KEY: AES-256 requires exactly 32 bytes (256 bits). Resolved key is ${keyBuffer.length} bytes.`
    );
  }

  return keyBuffer;
}

/**
 * Encrypts a plaintext Meta WhatsApp access token using authenticated AES-256-GCM.
 * Generates a cryptographically secure, unique 96-bit IV (12 bytes) for every encryption operation.
 * Produces a 128-bit authentication tag (16 bytes) to prevent ciphertext tampering.
 */
export function encryptWabaToken(
  plainToken: string,
  options?: {
    customKey?: string;
    keyId?: string;
    aad?: string;
  }
): EncryptedTokenMaterial {
  if (!plainToken || typeof plainToken !== 'string' || plainToken.trim().length === 0) {
    throw new Error('INVALID_TOKEN: Cannot encrypt an empty or non-string access token.');
  }

  const keyBuffer = resolveEncryptionKey(options?.customKey);
  const iv = crypto.randomBytes(12); // NIST SP 800-38D standard 96-bit IV
  const cipher = crypto.createCipheriv('aes-256-gcm', keyBuffer, iv);

  if (options?.aad) {
    cipher.setAAD(Buffer.from(options.aad, 'utf8'));
  }

  const encrypted = Buffer.concat([
    cipher.update(plainToken, 'utf8'),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();

  return {
    encryptedAccessToken: encrypted.toString('hex'),
    tokenIv: iv.toString('hex'),
    tokenTag: tag.toString('hex'),
    keyId: options?.keyId || 'v1',
  };
}

/**
 * Decrypts and authenticates an AES-256-GCM encrypted Meta WhatsApp access token.
 * Validates ciphertext authenticity using the GCM auth tag.
 * Fails closed if the ciphertext, IV, tag, or AAD has been tampered with or if the key is incorrect.
 */
export function decryptWabaToken(
  material: EncryptedTokenMaterial,
  options?: {
    customKey?: string;
    aad?: string;
  }
): string {
  if (!material || !material.encryptedAccessToken || !material.tokenIv || !material.tokenTag) {
    throw new Error('INVALID_ENCRYPTED_MATERIAL: Missing encrypted token, IV, or authentication tag.');
  }

  const keyBuffer = resolveEncryptionKey(options?.customKey);

  const ivBuffer = Buffer.from(material.tokenIv, 'hex');
  if (ivBuffer.length !== 12) {
    throw new Error('INVALID_IV: AES-256-GCM IV must be 12 bytes (24 hex characters).');
  }

  const tagBuffer = Buffer.from(material.tokenTag, 'hex');
  if (tagBuffer.length !== 16) {
    throw new Error('INVALID_TAG: AES-256-GCM authentication tag must be 16 bytes (32 hex characters).');
  }

  try {
    const decipher = crypto.createDecipheriv('aes-256-gcm', keyBuffer, ivBuffer);
    decipher.setAuthTag(tagBuffer);

    if (options?.aad) {
      decipher.setAAD(Buffer.from(options.aad, 'utf8'));
    }

    const decrypted = Buffer.concat([
      decipher.update(Buffer.from(material.encryptedAccessToken, 'hex')),
      decipher.final(),
    ]);

    return decrypted.toString('utf8');
  } catch (err: any) {
    throw new Error('DECRYPTION_FAILED: Token authentication failed or cipher material was tampered with.');
  }
}
