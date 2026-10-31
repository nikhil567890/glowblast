process.env.NODE_ENV = 'test';
process.env.WABA_TOKEN_ENCRYPTION_KEY =
  process.env.WABA_TOKEN_ENCRYPTION_KEY ||
  '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { app } from '../src/server';
import { env, envSchema, getWebhookVerifyToken } from '../src/config/env';
import { WebhookService } from '../src/services/webhookService';
import { prepareMigration012 } from '../src/db/migrator';
import {
  resolveInitialSpaCredentials,
  executeInitialSpaSetup,
} from '../scripts/setupInitialSpaConnection';
import { INITIAL_BUSINESS_ID } from '../src/middleware/authMiddleware';

test('Production Audit Blockers (B1 - B7) Regression Suite', async (t) => {
  const server = app.listen(0);
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : 0;
  const baseUrl = `http://127.0.0.1:${port}`;

  t.after(() => {
    server.close();
  });

  // ============================================================================
  // B1: Migration 012 Owner Selection & Safe Ambiguity Handling
  // ============================================================================
  await t.test('B1.1 - prepareMigration012 sets glowblast.initial_owner_email when valid verified owner provided', async () => {
    const executedQueries: { text: string; values?: any[] }[] = [];
    const mockClient: any = {
      query: async (text: string, values?: any[]) => {
        executedQueries.push({ text, values });
        if (text.includes('SELECT id, email_verified FROM users')) {
          // Return existing verified user
          return { rows: [{ id: 'usr_verified_123', email_verified: true }] };
        }
        if (text.includes('set_config')) {
          return { rows: [{ set_config: 'owner@example.com' }] };
        }
        return { rows: [] };
      },
    };

    await prepareMigration012(mockClient, 'owner@example.com');

    // Assert that set_config was called on the same client with is_local = true
    const setConfigCall = executedQueries.find((q) => q.text.includes('set_config'));
    assert.ok(setConfigCall, 'set_config must be executed');
    assert.match(setConfigCall.text, /set_config\('glowblast\.initial_owner_email',\s*\$1,\s*true\)/);
    assert.deepEqual(setConfigCall.values, ['owner@example.com']);
  });

  await t.test('B1.2 - prepareMigration012 aborts safely when configured email does not match any user without leaking email', async () => {
    const mockClient: any = {
      query: async (text: string) => {
        if (text.includes('SELECT id, email_verified FROM users')) {
          return { rows: [] }; // No matching user
        }
        return { rows: [] };
      },
    };

    let caughtError: Error | null = null;
    try {
      await prepareMigration012(mockClient, 'nonexistent_secret_user@example.com');
    } catch (err: any) {
      caughtError = err;
    }

    assert.ok(caughtError, 'Must throw error when owner email does not match user');
    assert.match(caughtError.message, /does not match any existing registered user/i);
    assert.strictEqual(
      caughtError.message.includes('nonexistent_secret_user@example.com'),
      false,
      'Error message must NOT leak the owner email'
    );
  });

  await t.test('B1.3 - prepareMigration012 aborts safely when configured user is not verified', async () => {
    const mockClient: any = {
      query: async (text: string) => {
        if (text.includes('SELECT id, email_verified FROM users')) {
          return { rows: [{ id: 'usr_unverified_456', email_verified: false }] };
        }
        return { rows: [] };
      },
    };

    let caughtError: Error | null = null;
    try {
      await prepareMigration012(mockClient, 'unverified_person@example.com');
    } catch (err: any) {
      caughtError = err;
    }

    assert.ok(caughtError, 'Must throw error when owner user is not verified');
    assert.match(caughtError.message, /verified user account/i);
    assert.strictEqual(
      caughtError.message.includes('unverified_person@example.com'),
      false,
      'Error message must NOT leak the unverified user email'
    );
  });

  await t.test('B1.4 - prepareMigration012 aborts safely when multiple verified users exist and no owner configured', async () => {
    const originalEnv = process.env.INITIAL_BUSINESS_OWNER_EMAIL;
    delete process.env.INITIAL_BUSINESS_OWNER_EMAIL;

    try {
      const mockClient: any = {
        query: async (text: string) => {
          if (text.includes('email_verified = true')) {
            return { rows: [{ count: '3' }] }; // 3 verified users
          }
          if (text.includes('SELECT COUNT(*) as count FROM users;')) {
            return { rows: [{ count: '5' }] };
          }
          return { rows: [] };
        },
      };

      let caughtError: Error | null = null;
      try {
        await prepareMigration012(mockClient);
      } catch (err: any) {
        caughtError = err;
      }

      assert.ok(caughtError, 'Must throw error when ownership is ambiguous');
      assert.match(caughtError.message, /Ambiguous initial business ownership/i);
      assert.match(caughtError.message, /Set INITIAL_BUSINESS_OWNER_EMAIL/i);
    } finally {
      if (originalEnv) {
        process.env.INITIAL_BUSINESS_OWNER_EMAIL = originalEnv;
      }
    }
  });

  await t.test('B1.5 - prepareMigration012 permits fresh install (0 users) and single verified user without error', async () => {
    const originalEnv = process.env.INITIAL_BUSINESS_OWNER_EMAIL;
    delete process.env.INITIAL_BUSINESS_OWNER_EMAIL;

    try {
      // 0 users (fresh install)
      const mockClientFresh: any = {
        query: async (text: string) => {
          if (text.includes('email_verified = true')) return { rows: [{ count: '0' }] };
          if (text.includes('SELECT COUNT(*) as count FROM users;')) return { rows: [{ count: '0' }] };
          return { rows: [] };
        },
      };
      await assert.doesNotReject(() => prepareMigration012(mockClientFresh));

      // 1 verified user (unambiguous sole owner)
      const mockClientSingle: any = {
        query: async (text: string) => {
          if (text.includes('email_verified = true')) return { rows: [{ count: '1' }] };
          if (text.includes('SELECT COUNT(*) as count FROM users;')) return { rows: [{ count: '1' }] };
          return { rows: [] };
        },
      };
      await assert.doesNotReject(() => prepareMigration012(mockClientSingle));
    } finally {
      if (originalEnv) {
        process.env.INITIAL_BUSINESS_OWNER_EMAIL = originalEnv;
      }
    }
  });

  // ============================================================================
  // B2: Initial Spa Display-Number Variables & Provisioning
  // ============================================================================
  await t.test('B2.1 - resolveInitialSpaCredentials resolves PROD_WHATSAPP_DISPLAY_NUMBER in production mode', () => {
    const creds = resolveInitialSpaCredentials('production');
    assert.strictEqual(creds.businessId, INITIAL_BUSINESS_ID);
    assert.strictEqual(creds.mode, 'production');
    assert.strictEqual(creds.displayNumber, env.PROD_WHATSAPP_DISPLAY_NUMBER);
    assert.strictEqual(creds.displayNumber, '+919502259203');
    assert.ok(creds.wabaId.length > 0);
    assert.ok(creds.phoneNumberId.length > 0);
  });

  await t.test('B2.2 - resolveInitialSpaCredentials resolves TEST_WHATSAPP_DISPLAY_NUMBER in test mode', () => {
    const creds = resolveInitialSpaCredentials('test');
    assert.strictEqual(creds.businessId, INITIAL_BUSINESS_ID);
    assert.strictEqual(creds.mode, 'test');
    assert.strictEqual(creds.displayNumber, env.TEST_WHATSAPP_DISPLAY_NUMBER);
    assert.strictEqual(creds.displayNumber, '+1 (555) 632-5494');
    assert.ok(creds.wabaId.length > 0);
    assert.ok(creds.phoneNumberId.length > 0);
  });

  await t.test('B2.3 - executeInitialSpaSetup dry-run verifies encryption round-trip with tenant-bound AAD', async () => {
    const testResult = await executeInitialSpaSetup({ mode: 'test', isDryRun: true });
    assert.strictEqual(testResult.dryRun, true);
    assert.ok(testResult.summary);
    assert.strictEqual(testResult.summary.businessId, INITIAL_BUSINESS_ID);
    assert.strictEqual(testResult.summary.mode, 'test');
    assert.strictEqual(testResult.summary.displayNumber, env.TEST_WHATSAPP_DISPLAY_NUMBER);
    assert.strictEqual(testResult.summary.ivLengthHex, 24); // 96 bits = 12 bytes = 24 hex chars
    assert.strictEqual(testResult.summary.tagLengthHex, 32); // 128 bits = 16 bytes = 32 hex chars

    const prodResult = await executeInitialSpaSetup({ mode: 'production', isDryRun: true });
    assert.strictEqual(prodResult.dryRun, true);
    assert.ok(prodResult.summary);
    assert.strictEqual(prodResult.summary.businessId, INITIAL_BUSINESS_ID);
    assert.strictEqual(prodResult.summary.mode, 'production');
    assert.strictEqual(prodResult.summary.displayNumber, env.PROD_WHATSAPP_DISPLAY_NUMBER);
    assert.strictEqual(prodResult.summary.ivLengthHex, 24);
    assert.strictEqual(prodResult.summary.tagLengthHex, 32);
  });

  // ============================================================================
  // B3: Meta Webhook Signature Verification
  // ============================================================================
  await t.test('B3.1 - WebhookService.verifySignature fails closed in production when META_APP_SECRET is missing', () => {
    const origEnv = process.env.NODE_ENV;
    const origSecret = process.env.META_APP_SECRET;
    const origEnvSecret = env.META_APP_SECRET;

    try {
      process.env.NODE_ENV = 'production';
      delete process.env.META_APP_SECRET;
      (env as any).META_APP_SECRET = undefined;

      const payload = JSON.stringify({ object: 'whatsapp_business_account', entry: [] });
      const isValid = WebhookService.verifySignature(payload, 'sha256=anyfakehash');
      assert.strictEqual(isValid, false, 'Must return false when META_APP_SECRET is missing in production');
    } finally {
      process.env.NODE_ENV = origEnv;
      if (origSecret) process.env.META_APP_SECRET = origSecret;
      (env as any).META_APP_SECRET = origEnvSecret;
    }
  });

  await t.test('B3.2 - WebhookService.verifySignature rejects missing, un-prefixed, or tampered signatures', () => {
    const testSecret = 'test_webhook_app_secret_32_bytes_xyz';
    const origSecret = process.env.META_APP_SECRET;
    const origEnvSecret = env.META_APP_SECRET;

    try {
      process.env.META_APP_SECRET = testSecret;
      (env as any).META_APP_SECRET = testSecret;

      const payload = JSON.stringify({ object: 'whatsapp_business_account', entry: [] });

      // Missing signature
      assert.strictEqual(WebhookService.verifySignature(payload, undefined), false);

      // Malformed signature (missing sha256= prefix)
      assert.strictEqual(WebhookService.verifySignature(payload, 'abc12345'), false);

      // Wrong signature
      assert.strictEqual(WebhookService.verifySignature(payload, 'sha256=0000000000000000000000000000000000000000000000000000000000000000'), false);

      // Valid HMAC signature
      const validHmac = crypto.createHmac('sha256', testSecret).update(payload).digest('hex');
      assert.strictEqual(WebhookService.verifySignature(payload, `sha256=${validHmac}`), true);

      // Tampered payload
      const tamperedPayload = JSON.stringify({ object: 'whatsapp_business_account', entry: [{ tampered: true }] });
      assert.strictEqual(WebhookService.verifySignature(tamperedPayload, `sha256=${validHmac}`), false);
    } finally {
      if (origSecret) process.env.META_APP_SECRET = origSecret;
      else delete process.env.META_APP_SECRET;
      (env as any).META_APP_SECRET = origEnvSecret;
    }
  });

  await t.test('B3.3 - POST /api/webhook/whatsapp rejects invalid signature with HTTP 403 before processing', async () => {
    const testSecret = 'secret_key_for_http_signature_test_123';
    const origSecret = process.env.META_APP_SECRET;
    const origEnvSecret = env.META_APP_SECRET;

    try {
      process.env.META_APP_SECRET = testSecret;
      (env as any).META_APP_SECRET = testSecret;

      const payload = JSON.stringify({
        object: 'whatsapp_business_account',
        entry: [{ id: 'fake_entry', changes: [] }],
      });

      // 1. Invalid signature
      const resInvalid = await fetch(`${baseUrl}/api/webhook/whatsapp`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Hub-Signature-256': 'sha256=invalidhex000000000000000000000000000000000000000000000000000000000',
        },
        body: payload,
      });
      assert.strictEqual(resInvalid.status, 403, 'Invalid signature must receive 403 Forbidden');

      // 2. Missing signature
      const resMissing = await fetch(`${baseUrl}/api/webhook/whatsapp`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: payload,
      });
      assert.strictEqual(resMissing.status, 403, 'Missing signature must receive 403 Forbidden');

      // 3. Valid signature against raw body
      const validHmac = crypto.createHmac('sha256', testSecret).update(payload).digest('hex');
      const resValid = await fetch(`${baseUrl}/api/webhook/whatsapp`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Hub-Signature-256': `sha256=${validHmac}`,
        },
        body: payload,
      });
      assert.strictEqual(resValid.status, 200, 'Valid signature must receive 200 OK');
    } finally {
      if (origSecret) process.env.META_APP_SECRET = origSecret;
      else delete process.env.META_APP_SECRET;
      (env as any).META_APP_SECRET = origEnvSecret;
    }
  });

  await t.test('B3.4 - GET /api/webhook/whatsapp challenge handling is preserved', async () => {
    const challenge = 'test_challenge_string_778899';
    const res = await fetch(
      `${baseUrl}/api/webhook/whatsapp?hub.mode=subscribe&hub.verify_token=${env.META_VERIFY_TOKEN}&hub.challenge=${challenge}`
    );
    assert.strictEqual(res.status, 200);
    const text = await res.text();
    assert.strictEqual(text, challenge);
  });

  // ============================================================================
  // B4: Elimination of Hardcoded Verify Token in Production
  // ============================================================================
  await t.test('B4.1 - Production env validation strictly rejects default glowblast_webhook_verify_token', () => {
    const prodEnvWithDefault = {
      NODE_ENV: 'production',
      META_APP_SECRET: 'my_production_meta_app_secret_123',
      META_VERIFY_TOKEN: 'glowblast_webhook_verify_token', // default
    };

    const parsed = envSchema.safeParse(prodEnvWithDefault);
    assert.strictEqual(parsed.success, false, 'Production schema must reject default verify token');
    const issues = (parsed as any).error.issues;
    const tokenIssue = issues.find((i: any) => i.path.includes('META_VERIFY_TOKEN'));
    assert.ok(tokenIssue, 'Must contain issue for META_VERIFY_TOKEN');
  });

  await t.test('B4.2 - Production env validation strictly rejects missing META_APP_SECRET', () => {
    const prodEnvMissingSecret = {
      NODE_ENV: 'production',
      META_VERIFY_TOKEN: 'my_secure_random_production_token_12345',
      // META_APP_SECRET omitted
    };

    const parsed = envSchema.safeParse(prodEnvMissingSecret);
    assert.strictEqual(parsed.success, false, 'Production schema must reject missing META_APP_SECRET');
    const issues = (parsed as any).error.issues;
    const secretIssue = issues.find((i: any) => i.path.includes('META_APP_SECRET'));
    assert.ok(secretIssue, 'Must contain issue for META_APP_SECRET');
  });

  await t.test('B4.3 - getWebhookVerifyToken throws in production if token is empty or predictable default', () => {
    const origEnv = process.env.NODE_ENV;
    const origVerify = process.env.META_VERIFY_TOKEN;
    const origWhVerify = process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN;

    try {
      process.env.NODE_ENV = 'production';
      process.env.META_VERIFY_TOKEN = 'glowblast_webhook_verify_token';
      delete process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN;

      assert.throws(
        () => getWebhookVerifyToken(),
        /forbidden in production/i
      );

      delete process.env.META_VERIFY_TOKEN;
      (env as any).META_VERIFY_TOKEN = undefined;
      assert.throws(
        () => getWebhookVerifyToken(),
        /required in production/i
      );
    } finally {
      process.env.NODE_ENV = origEnv;
      if (origVerify) process.env.META_VERIFY_TOKEN = origVerify;
      else delete process.env.META_VERIFY_TOKEN;
      (env as any).META_VERIFY_TOKEN = origVerify;
      if (origWhVerify) process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN = origWhVerify;
      else delete process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN;
    }
  });

  // ============================================================================
  // B5: CORS Allowed Headers includes X-Business-Id
  // ============================================================================
  await t.test('B5.1 - CORS preflight accepts X-Business-Id header alongside Content-Type and Authorization', async () => {
    const res = await fetch(`${baseUrl}/api/businesses`, {
      method: 'OPTIONS',
      headers: {
        Origin: 'http://localhost:8080',
        'Access-Control-Request-Method': 'POST',
        'Access-Control-Request-Headers': 'Content-Type, Authorization, X-Business-Id',
      },
    });

    assert.strictEqual(res.status, 204, 'Preflight request must return 204 No Content');
    const allowedHeaders = res.headers.get('access-control-allow-headers');
    assert.ok(allowedHeaders, 'access-control-allow-headers header must be present');

    const headersList = allowedHeaders.split(',').map((h) => h.trim().toLowerCase());
    assert.ok(headersList.includes('x-business-id'), 'X-Business-Id must be in allowedHeaders');
    assert.ok(headersList.includes('content-type'), 'Content-Type must be in allowedHeaders');
    assert.ok(headersList.includes('authorization'), 'Authorization must be in allowedHeaders');
  });

  // ============================================================================
  // B6 & B7: Environment Documentation in backend/.env.example
  // ============================================================================
  await t.test('B6 & B7 - backend/.env.example documents all canonical variables and secure generation instructions', () => {
    const candidates = [
      path.resolve(__dirname, '../../.env.example'),
      path.resolve(__dirname, '../.env.example'),
      path.resolve(process.cwd(), '.env.example'),
      path.resolve(process.cwd(), 'backend/.env.example'),
    ];
    const envExamplePath = candidates.find((c) => fs.existsSync(c)) || candidates[0];
    assert.ok(fs.existsSync(envExamplePath), 'backend/.env.example must exist');

    const content = fs.readFileSync(envExamplePath, 'utf8');

    // Canonical encryption key & alias
    assert.ok(content.includes('WABA_TOKEN_ENCRYPTION_KEY='), 'Must document WABA_TOKEN_ENCRYPTION_KEY');
    assert.ok(content.includes('WABA_ENCRYPTION_KEY='), 'Must document WABA_ENCRYPTION_KEY alias');
    assert.ok(content.includes('32 cryptographically secure random bytes'), 'Must document 32 bytes requirement');
    assert.ok(content.includes('randomBytes(32)'), 'Must include key generation instructions');

    // Brevo variables
    assert.ok(content.includes('BREVO_API_KEY='), 'Must document BREVO_API_KEY');
    assert.ok(content.includes('BREVO_SENDER_EMAIL='), 'Must document BREVO_SENDER_EMAIL');
    assert.ok(content.includes('BREVO_SENDER_NAME='), 'Must document BREVO_SENDER_NAME');

    // Meta App security & verify token
    assert.ok(content.includes('META_APP_SECRET='), 'Must document META_APP_SECRET');
    assert.ok(content.includes('META_VERIFY_TOKEN='), 'Must document META_VERIFY_TOKEN');
    assert.strictEqual(
      content.includes('META_VERIFY_TOKEN=glowblast_webhook_verify_token'),
      false,
      'Must NOT contain hardcoded default verify token in .env.example'
    );

    // Migration-only owner setting
    assert.ok(content.includes('INITIAL_BUSINESS_OWNER_EMAIL='), 'Must document INITIAL_BUSINESS_OWNER_EMAIL');
    assert.ok(content.includes('migration-only'), 'Must explicitly note it is migration-only');
  });
});
