process.env.NODE_ENV = 'test';
import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'crypto';
import bcrypt from 'bcryptjs';
import { userStore } from '../src/store/userStore';
import { getSafeConfigStatus, getSafeBrevoStatus } from '../src/config/env';

test('Brevo Configuration & Security', async (t) => {
  await t.test('getSafeBrevoStatus never leaks BREVO_API_KEY', () => {
    const status = getSafeBrevoStatus();
    assert.strictEqual('apiKey' in status, false);
    assert.strictEqual('BREVO_API_KEY' in status, false);
    assert.strictEqual(typeof status.configured, 'boolean');
  });

  await t.test('getSafeConfigStatus includes brevoConfigured without secret leakage', () => {
    const status = getSafeConfigStatus();
    assert.strictEqual('apiKey' in status, false);
    assert.strictEqual(typeof status.brevoConfigured, 'boolean');
  });
});

test('Auth Store & OTP Security', async (t) => {
  userStore.clear();

  const testEmail = 'priya.sharma@example.com';
  const testPassword = 'Password123!';
  const rawOtp = '482910';
  const otpHash = crypto.createHash('sha256').update(rawOtp).digest('hex');
  const passwordHash = await bcrypt.hash(testPassword, 10);

  await t.test('Saves OTP with 10-minute expiry and hashes securely', () => {
    userStore.saveOtp({
      email: testEmail,
      name: 'Priya Sharma',
      passwordHash,
      otpHash,
      expiresAt: Date.now() + 10 * 60 * 1000,
      attempts: 0,
      createdAt: Date.now(),
      lastRequestedAt: Date.now(),
    });

    const record = userStore.getOtp(testEmail);
    assert.ok(record);
    assert.strictEqual(record.email, testEmail);
    assert.strictEqual(record.otpHash, otpHash);
    // Ensure raw OTP was NOT stored
    assert.notStrictEqual(record.otpHash, rawOtp);
  });

  await t.test('Incrementing attempts tracks failed verification tries', () => {
    const attempts1 = userStore.incrementOtpAttempts(testEmail);
    assert.strictEqual(attempts1, 1);
    const attempts2 = userStore.incrementOtpAttempts(testEmail);
    assert.strictEqual(attempts2, 2);
  });

  await t.test('Password verification with bcrypt works correctly', async () => {
    const valid = await bcrypt.compare(testPassword, passwordHash);
    assert.strictEqual(valid, true);

    const invalid = await bcrypt.compare('WrongPassword', passwordHash);
    assert.strictEqual(invalid, false);
  });

  await t.test('Creating verified user and ensuring passwordHash is excluded from SafeUser', () => {
    const user = userStore.saveUser({
      id: 'usr_test_123',
      name: 'Priya Sharma',
      email: testEmail,
      passwordHash,
      emailVerified: true,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      lastLoginAt: new Date().toISOString(),
    });

    const safe = userStore.toSafeUser(user);
    assert.strictEqual('passwordHash' in safe, false);
    assert.strictEqual(safe.email, testEmail);
    assert.strictEqual(safe.name, 'Priya Sharma');
  });

  await t.test('Preserves businessName and phone in OtpRecord and User', () => {
    userStore.saveOtp({
      email: 'aura@example.com',
      name: 'Pooja',
      passwordHash,
      otpHash,
      businessName: 'Aura Luxury Spa',
      phone: '+91 98765 43210',
      expiresAt: Date.now() + 600000,
      attempts: 0,
      createdAt: Date.now(),
      lastRequestedAt: Date.now(),
    });

    const otp = userStore.getOtp('aura@example.com');
    assert.strictEqual(otp?.businessName, 'Aura Luxury Spa');
    assert.strictEqual(otp?.phone, '+91 98765 43210');

    const created = userStore.saveUser({
      id: 'usr_aura',
      name: 'Pooja',
      email: 'aura@example.com',
      passwordHash,
      businessName: otp?.businessName,
      phone: otp?.phone,
      emailVerified: true,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });

    const safe = userStore.toSafeUser(created);
    assert.strictEqual(safe.businessName, 'Aura Luxury Spa');
    assert.strictEqual(safe.phone, '+91 98765 43210');
  });

  await t.test('Deleting OTP makes it single-use', () => {
    userStore.deleteOtp(testEmail);
    const record = userStore.getOtp(testEmail);
    assert.strictEqual(record, undefined);
  });
});

test('Express App Auth Endpoints Mounting', async (t) => {
  const { app } = await import('../src/server');

  await t.test('Route mounting exposes auth endpoints under /api/auth', async () => {
    const server = app.listen(0);
    const address = server.address();
    const port = typeof address === 'object' && address ? address.port : 0;
    const baseUrl = `http://127.0.0.1:${port}`;

    try {
      // 1. POST /api/auth/register/request-otp (validation check)
      const res1 = await fetch(`${baseUrl}/api/auth/register/request-otp`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({}),
      });
      // Should be 400 Validation Error, NOT 404 NOT_FOUND!
      assert.strictEqual(res1.status, 400);
      const data1 = await res1.json() as any;
      assert.strictEqual(data1.error?.code, 'VALIDATION_ERROR');

      // 2. POST /api/auth/register/verify-otp (validation check)
      const res2 = await fetch(`${baseUrl}/api/auth/register/verify-otp`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({}),
      });
      assert.strictEqual(res2.status, 400);

      // 3. POST /api/auth/login (validation check)
      const res3 = await fetch(`${baseUrl}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({}),
      });
      assert.strictEqual(res3.status, 400);

      // 4. GET /api/auth/me (unauthorized check)
      const res4 = await fetch(`${baseUrl}/api/auth/me`);
      assert.strictEqual(res4.status, 401);

      // 5. POST /api/auth/logout
      const res5 = await fetch(`${baseUrl}/api/auth/logout`, { method: 'POST' });
      assert.strictEqual(res5.status, 200);
    } finally {
      server.close();
    }
  });
});
