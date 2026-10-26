process.env.NODE_ENV = 'test';
import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'crypto';
import {
  resolveEncryptionKey,
  encryptWabaToken,
  decryptWabaToken,
  EncryptedTokenMaterial,
} from '../src/utils/tokenEncryption';

test('WABA Access Token Authenticated Encryption (AES-256-GCM) Test Suite', async (t) => {
  // Generate random 32-byte valid keys for testing
  const validHexKey = crypto.randomBytes(32).toString('hex');
  const validBase64Key = crypto.randomBytes(32).toString('base64');
  const valid32ByteUtf8Key = 'my_super_secret_32_byte_key_123!';

  await t.test('1. resolveEncryptionKey parses 64-hex, base64, and 32-byte utf8 keys to exactly 32-byte Buffer', () => {
    const k1 = resolveEncryptionKey(validHexKey);
    assert.strictEqual(k1.length, 32);

    const k2 = resolveEncryptionKey(validBase64Key);
    assert.strictEqual(k2.length, 32);

    const k3 = resolveEncryptionKey(valid32ByteUtf8Key);
    assert.strictEqual(k3.length, 32);
  });

  await t.test('2. resolveEncryptionKey fails closed when key is missing or empty', () => {
    assert.throws(
      () => resolveEncryptionKey(''),
      /ENCRYPTION_KEY_MISSING/
    );
    assert.throws(
      () => resolveEncryptionKey(undefined),
      /ENCRYPTION_KEY_MISSING/
    );
  });

  await t.test('3. resolveEncryptionKey fails closed when key length is invalid', () => {
    // Too short (16 bytes = 32 hex chars)
    assert.throws(
      () => resolveEncryptionKey('abcdef0123456789abcdef0123456789'),
      /INVALID_ENCRYPTION_KEY/
    );
    // Non-hex random short string
    assert.throws(
      () => resolveEncryptionKey('short_insecure_key'),
      /INVALID_ENCRYPTION_KEY/
    );
    // Too long (48 bytes = 96 hex chars)
    const longHex = crypto.randomBytes(48).toString('hex');
    assert.throws(
      () => resolveEncryptionKey(longHex),
      /INVALID_ENCRYPTION_KEY/
    );
  });

  await t.test('4. Encrypt and Decrypt round-trip successfully recovers plaintext token', () => {
    const token = 'EAAcInZBNIfBwBShLNNd9ZABWJqhqXbFiOkbsRpRB4TOY7XZAc2EQTt2kuGvDXEXj8ZCRMD52QZBJyD6ZAItxeXXoacsZBp0T70hk3lZASpli9ivplQ';
    const encrypted = encryptWabaToken(token, { customKey: validHexKey, keyId: 'v1' });

    assert.ok(encrypted.encryptedAccessToken, 'Encrypted access token must exist');
    assert.ok(encrypted.tokenIv, 'IV must exist');
    assert.ok(encrypted.tokenTag, 'Tag must exist');
    assert.strictEqual(encrypted.keyId, 'v1');

    // Token must NOT appear in raw ciphertext or IV/tag
    assert.strictEqual(encrypted.encryptedAccessToken.includes(token), false);
    assert.strictEqual(encrypted.tokenIv.includes(token), false);
    assert.strictEqual(encrypted.tokenTag.includes(token), false);

    // IV must be 12 bytes = 24 hex characters
    assert.strictEqual(encrypted.tokenIv.length, 24);
    // Tag must be 16 bytes = 32 hex characters
    assert.strictEqual(encrypted.tokenTag.length, 32);

    const decrypted = decryptWabaToken(encrypted, { customKey: validHexKey });
    assert.strictEqual(decrypted, token);
  });

  await t.test('5. Nonce/IV uniqueness: Two encryptions of same plaintext produce distinct IVs and ciphertexts', () => {
    const token = 'EAAB_SAME_TOKEN_FOR_BOTH';
    const enc1 = encryptWabaToken(token, { customKey: validHexKey });
    const enc2 = encryptWabaToken(token, { customKey: validHexKey });

    assert.notStrictEqual(enc1.tokenIv, enc2.tokenIv, 'IVs must be uniquely generated for each operation');
    assert.notStrictEqual(enc1.encryptedAccessToken, enc2.encryptedAccessToken, 'Ciphertexts must differ due to unique IV');
    assert.notStrictEqual(enc1.tokenTag, enc2.tokenTag, 'Auth tags must differ');

    // Both decrypt to identical plaintext
    assert.strictEqual(decryptWabaToken(enc1, { customKey: validHexKey }), token);
    assert.strictEqual(decryptWabaToken(enc2, { customKey: validHexKey }), token);
  });

  await t.test('6. Tampering detection: Altering ciphertext fails closed with DECRYPTION_FAILED', () => {
    const token = 'EAA_TEST_SECRET_TOKEN_XYZ';
    const enc = encryptWabaToken(token, { customKey: validHexKey });

    // Flip a single character in ciphertext
    const tamperedHex = enc.encryptedAccessToken.slice(0, -2) + (enc.encryptedAccessToken.slice(-2) === 'aa' ? 'bb' : 'aa');
    const tamperedMaterial: EncryptedTokenMaterial = {
      ...enc,
      encryptedAccessToken: tamperedHex,
    };

    assert.throws(
      () => decryptWabaToken(tamperedMaterial, { customKey: validHexKey }),
      /DECRYPTION_FAILED/
    );
  });

  await t.test('7. Tampering detection: Altering authentication tag fails closed with DECRYPTION_FAILED', () => {
    const token = 'EAA_TEST_SECRET_TOKEN_XYZ';
    const enc = encryptWabaToken(token, { customKey: validHexKey });

    // Corrupt the authentication tag
    const tamperedTag = '0000000000000000' + enc.tokenTag.slice(16);
    const tamperedMaterial: EncryptedTokenMaterial = {
      ...enc,
      tokenTag: tamperedTag,
    };

    assert.throws(
      () => decryptWabaToken(tamperedMaterial, { customKey: validHexKey }),
      /DECRYPTION_FAILED/
    );
  });

  await t.test('8. Tampering detection: Altering IV fails closed with DECRYPTION_FAILED', () => {
    const token = 'EAA_TEST_SECRET_TOKEN_XYZ';
    const enc = encryptWabaToken(token, { customKey: validHexKey });

    // Corrupt the IV
    const tamperedIv = '1111111111111111' + enc.tokenIv.slice(16);
    const tamperedMaterial: EncryptedTokenMaterial = {
      ...enc,
      tokenIv: tamperedIv,
    };

    assert.throws(
      () => decryptWabaToken(tamperedMaterial, { customKey: validHexKey }),
      /DECRYPTION_FAILED/
    );
  });

  await t.test('9. Authenticated Additional Data (AAD) binding prevents cross-tenant token transplant', () => {
    const token = 'EAA_TENANT_BOUND_TOKEN';
    const tenantA = 'a0000000-0000-4000-8000-000000000001';
    const tenantB = 'b0000000-0000-4000-8000-000000000002';

    // Encrypt token bound to Tenant A
    const encTenantA = encryptWabaToken(token, { customKey: validHexKey, aad: tenantA });

    // Successfully decrypts with Tenant A context
    const decrypted = decryptWabaToken(encTenantA, { customKey: validHexKey, aad: tenantA });
    assert.strictEqual(decrypted, token);

    // Attempting to decrypt with Tenant B context fails closed!
    assert.throws(
      () => decryptWabaToken(encTenantA, { customKey: validHexKey, aad: tenantB }),
      /DECRYPTION_FAILED/
    );
  });

  await t.test('10. Decrypting with wrong key fails closed with DECRYPTION_FAILED', () => {
    const token = 'EAA_WRONG_KEY_TEST';
    const enc = encryptWabaToken(token, { customKey: validHexKey });

    const wrongKey = crypto.randomBytes(32).toString('hex');
    assert.throws(
      () => decryptWabaToken(enc, { customKey: wrongKey }),
      /DECRYPTION_FAILED/
    );
  });

  await t.test('11. Empty or whitespace token is rejected at encryption time', () => {
    assert.throws(
      () => encryptWabaToken('', { customKey: validHexKey }),
      /INVALID_TOKEN/
    );
    assert.throws(
      () => encryptWabaToken('   ', { customKey: validHexKey }),
      /INVALID_TOKEN/
    );
  });

  await t.test('12. Standardized key resolution supports WABA_ENCRYPTION_KEY alias without breaking decryption', () => {
    const testSecretKey = crypto.randomBytes(32).toString('hex');
    const token = 'EAA_ALIAS_COMPATIBILITY_TOKEN_TEST';

    // 1. Simulate encrypting when WABA_TOKEN_ENCRYPTION_KEY is set
    delete process.env.WABA_TOKEN_ENCRYPTION_KEY;
    delete process.env.WABA_ENCRYPTION_KEY;
    process.env.WABA_TOKEN_ENCRYPTION_KEY = testSecretKey;

    const enc = encryptWabaToken(token, { aad: 'biz_alias_test' });

    // 2. Simulate renaming the variable in environment to WABA_ENCRYPTION_KEY
    delete process.env.WABA_TOKEN_ENCRYPTION_KEY;
    process.env.WABA_ENCRYPTION_KEY = testSecretKey;

    // Must still decrypt successfully with exact same key under new variable name
    const dec = decryptWabaToken(enc, { aad: 'biz_alias_test' });
    assert.strictEqual(dec, token);

    // Clean up
    delete process.env.WABA_ENCRYPTION_KEY;
  });
});
