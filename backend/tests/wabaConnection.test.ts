process.env.NODE_ENV = 'test';
process.env.WABA_TOKEN_ENCRYPTION_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

import test from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import { app } from '../src/server';
import { env } from '../src/config/env';
import { businessStore } from '../src/store/businessStore';
import { wabaConnectionStore } from '../src/store/wabaConnectionStore';
import { messageStore } from '../src/store/messageStore';
import { consentStore } from '../src/store/consentStore';
import { campaignStore } from '../src/store/campaignStore';
import { Business, BusinessMember } from '../src/types/business';
import { StoredMessage, MessageStatus } from '../src/types/message';
import { resolveBusinessWhatsAppCredentials } from '../src/services/credentialResolver';
import { WebhookService } from '../src/services/webhookService';

test('Secure Per-Business WhatsApp Connections Test Suite', async (t) => {
  const server = app.listen(0);
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : 0;
  const baseUrl = `http://127.0.0.1:${port}`;

  t.after(() => {
    server.close();
  });

  const INITIAL_BIZ_ID = 'a0000000-0000-4000-8000-000000000001';
  const BIZ_A_ID = '11111111-1111-4000-8000-111111111111';
  const BIZ_B_ID = '22222222-2222-4000-8000-222222222222';
  const BIZ_NO_WABA_ID = '33333333-3333-4000-8000-333333333333';

  const userOwnerA = 'usr_owner_a';
  const userOwnerB = 'usr_owner_b';
  const userNoWaba = 'usr_owner_no_waba';
  const userInitial = 'usr_owner_initial';

  const tokenOwnerA = jwt.sign(
    { sub: userOwnerA, email: 'owner@spa-a.com', name: 'Owner A' },
    env.JWT_SECRET,
    { expiresIn: '1h' }
  );

  const tokenOwnerB = jwt.sign(
    { sub: userOwnerB, email: 'owner@spa-b.com', name: 'Owner B' },
    env.JWT_SECRET,
    { expiresIn: '1h' }
  );

  const tokenNoWaba = jwt.sign(
    { sub: userNoWaba, email: 'owner@nowaba.com', name: 'Owner No Waba' },
    env.JWT_SECRET,
    { expiresIn: '1h' }
  );

  const tokenInitial = jwt.sign(
    { sub: userInitial, email: 'owner@initial.com', name: 'Owner Initial' },
    env.JWT_SECRET,
    { expiresIn: '1h' }
  );

  // Setup Mock Businesses & Memberships
  const mockBusinesses = new Map<string, Business>();
  const mockMembers = new Map<string, BusinessMember[]>();

  const now = new Date();
  const bizA: Business = {
    id: BIZ_A_ID,
    displayName: 'Serenity Spa A',
    slug: 'serenity-spa-a',
    ownerUserId: userOwnerA,
    timezone: 'UTC',
    productionEnabled: false,
    dailyRecipientLimit: 200,
    isActive: true,
    createdAt: now,
    updatedAt: now,
  };
  const bizB: Business = {
    id: BIZ_B_ID,
    displayName: 'Lotus Wellness B',
    slug: 'lotus-wellness-b',
    ownerUserId: userOwnerB,
    timezone: 'UTC',
    productionEnabled: false,
    dailyRecipientLimit: 200,
    isActive: true,
    createdAt: now,
    updatedAt: now,
  };
  const bizNoWaba: Business = {
    id: BIZ_NO_WABA_ID,
    displayName: 'Unconnected Spa C',
    slug: 'unconnected-spa-c',
    ownerUserId: userNoWaba,
    timezone: 'UTC',
    productionEnabled: false,
    dailyRecipientLimit: 200,
    isActive: true,
    createdAt: now,
    updatedAt: now,
  };
  const bizInitial: Business = {
    id: INITIAL_BIZ_ID,
    displayName: 'Flagship Spa Initial',
    slug: 'flagship-spa-initial',
    ownerUserId: userInitial,
    timezone: 'UTC',
    productionEnabled: false,
    dailyRecipientLimit: 200,
    isActive: true,
    createdAt: now,
    updatedAt: now,
  };

  mockBusinesses.set(BIZ_A_ID, bizA);
  mockBusinesses.set(BIZ_B_ID, bizB);
  mockBusinesses.set(BIZ_NO_WABA_ID, bizNoWaba);
  mockBusinesses.set(INITIAL_BIZ_ID, bizInitial);

  mockMembers.set(userOwnerA, [
    { id: 'mem_a', businessId: BIZ_A_ID, userId: userOwnerA, role: 'owner', joinedAt: now, updatedAt: now },
  ]);
  mockMembers.set(userOwnerB, [
    { id: 'mem_b', businessId: BIZ_B_ID, userId: userOwnerB, role: 'owner', joinedAt: now, updatedAt: now },
  ]);
  mockMembers.set(userNoWaba, [
    { id: 'mem_c', businessId: BIZ_NO_WABA_ID, userId: userNoWaba, role: 'owner', joinedAt: now, updatedAt: now },
  ]);
  mockMembers.set(userInitial, [
    { id: 'mem_init', businessId: INITIAL_BIZ_ID, userId: userInitial, role: 'owner', joinedAt: now, updatedAt: now },
  ]);

  // Monkey-patch businessStore for test execution
  businessStore.findById = async (id: string) => mockBusinesses.get(id) || null;
  businessStore.getMember = async (bizId: string, userId: string) => {
    const list = mockMembers.get(userId) || [];
    return list.find((m) => m.businessId === bizId) || null;
  };
  businessStore.findByUserId = async (userId: string) => {
    const members = mockMembers.get(userId) || [];
    return members
      .map((m) => mockBusinesses.get(m.businessId))
      .filter((b): b is Business => Boolean(b && b.isActive));
  };

  // In-memory mocks for messageStore, consentStore, and campaignStore during tests
  const memoryMessages = new Map<string, StoredMessage>();
  messageStore.upsert = async (msg: StoredMessage) => {
    memoryMessages.set(msg.id, { ...msg });
    return msg;
  };
  messageStore.get = async (id: string, businessId?: string) => {
    const m = memoryMessages.get(id);
    if (!m) return undefined;
    if (businessId && m.businessId && m.businessId !== businessId) return undefined;
    return m;
  };
  messageStore.getByProviderId = async (providerId: string, businessId?: string) => {
    for (const m of memoryMessages.values()) {
      if (m.providerMessageId === providerId) {
        if (businessId && m.businessId && m.businessId !== businessId) return undefined;
        return m;
      }
    }
    return undefined;
  };
  messageStore.updateStatus = async (
    id: string,
    status: MessageStatus,
    providerMessageId?: string,
    error?: any
  ) => {
    const m = memoryMessages.get(id);
    if (!m) return undefined;
    m.status = status;
    if (providerMessageId) m.providerMessageId = providerMessageId;
    return m;
  };

  const memoryConsent = new Map<string, string>();
  consentStore.recordConsent = async (params: any) => {
    const effectiveBiz = params.businessId || INITIAL_BIZ_ID;
    memoryConsent.set(`${effectiveBiz}:${params.phone}`, params.status);
    return null;
  };
  consentStore.getConsent = async (phone: string, category?: any, bizId?: string) => {
    const effectiveBiz = bizId || INITIAL_BIZ_ID;
    const status = memoryConsent.get(`${effectiveBiz}:${phone}`);
    if (!status) return undefined;
    return {
      phone,
      consentCategory: category || 'marketing',
      status: status as any,
      recordedAt: new Date().toISOString(),
      source: 'test',
      evidence: 'test',
      updatedBy: 'test',
    };
  };

  campaignStore.recalculateAndSaveCampaignStatus = async (campId: string, bizId?: string) => {
    return undefined;
  };

  // Provision WABA connections for Business A and B
  const tokenA = 'EAAB_BIZ_A_SECRET_TOKEN_XYZ123';
  const tokenB = 'EAAB_BIZ_B_SECRET_TOKEN_ABC789';

  const phoneA = 'phone_id_biz_a_12345';
  const phoneB = 'phone_id_biz_b_67890';

  const wabaA = 'waba_id_biz_a_99999';
  const wabaB = 'waba_id_biz_b_88888';

  await wabaConnectionStore.saveConnection({
    businessId: BIZ_A_ID,
    wabaId: wabaA,
    phoneNumberId: phoneA,
    displayNumber: '+1 (555) 111-1111',
    mode: 'test',
    plainAccessToken: tokenA,
    verifiedName: 'Serenity Spa A Official',
  });

  await wabaConnectionStore.saveConnection({
    businessId: BIZ_B_ID,
    wabaId: wabaB,
    phoneNumberId: phoneB,
    displayNumber: '+1 (555) 222-2222',
    mode: 'test',
    plainAccessToken: tokenB,
    verifiedName: 'Lotus Wellness B Official',
  });

  await t.test('1. Separate encrypted WABA connections for Business A and B', async () => {
    const connA = await wabaConnectionStore.getActiveConnection(BIZ_A_ID, 'test');
    const connB = await wabaConnectionStore.getActiveConnection(BIZ_B_ID, 'test');

    assert.ok(connA, 'Business A must have an active connection');
    assert.ok(connB, 'Business B must have an active connection');

    assert.equal(connA?.phoneNumberId, phoneA);
    assert.equal(connB?.phoneNumberId, phoneB);
    assert.equal(connA?.wabaId, wabaA);
    assert.equal(connB?.wabaId, wabaB);

    // Verify IVs are distinct cryptographically secure nonces
    assert.notEqual(connA?.tokenIv, connB?.tokenIv);
    assert.notEqual(connA?.encryptedAccessToken, connB?.encryptedAccessToken);
  });

  await t.test('2. Tokens encrypt and decrypt correctly without appearing in API responses', async () => {
    // Check GET /api/whatsapp/connection for Business A
    const resA = await fetch(`${baseUrl}/api/whatsapp/connection?mode=test`, {
      headers: {
        Authorization: `Bearer ${tokenOwnerA}`,
        'X-Business-Id': BIZ_A_ID,
      },
    });

    assert.equal(resA.status, 200);
    const bodyA = await resA.json();

    assert.equal(bodyA.connected, true);
    assert.equal(bodyA.connection.wabaId, wabaA);
    assert.equal(bodyA.connection.phoneNumberId, phoneA);

    // CRITICAL SECURITY ASSERTION: No encrypted or raw token fields exposed in response
    assert.equal(bodyA.connection.encryptedAccessToken, undefined);
    assert.equal(bodyA.connection.tokenIv, undefined);
    assert.equal(bodyA.connection.tokenTag, undefined);
    assert.equal(bodyA.connection.rawAccessToken, undefined);
    assert.equal(JSON.stringify(bodyA).includes(tokenA), false);

    // Verify Business B sees its own connection and never A's
    const resB = await fetch(`${baseUrl}/api/whatsapp/connection?mode=test`, {
      headers: {
        Authorization: `Bearer ${tokenOwnerB}`,
        'X-Business-Id': BIZ_B_ID,
      },
    });

    assert.equal(resB.status, 200);
    const bodyB = await resB.json();
    assert.equal(bodyB.connection.wabaId, wabaB);
    assert.equal(bodyB.connection.phoneNumberId, phoneB);
    assert.equal(JSON.stringify(bodyB).includes(tokenB), false);
  });

  await t.test('3. Unconnected business returns connected=false and fails to send', async () => {
    const resCheck = await fetch(`${baseUrl}/api/whatsapp/connection?mode=test`, {
      headers: {
        Authorization: `Bearer ${tokenNoWaba}`,
        'X-Business-Id': BIZ_NO_WABA_ID,
      },
    });

    assert.equal(resCheck.status, 200);
    const bodyCheck = await resCheck.json();
    assert.equal(bodyCheck.connected, false);
    assert.equal(bodyCheck.connection, null);

    // Attempting direct send returns 403 WHATSAPP_CONNECTION_NOT_CONFIGURED
    const resSend = await fetch(`${baseUrl}/api/whatsapp/send`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${tokenNoWaba}`,
        'X-Business-Id': BIZ_NO_WABA_ID,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        phone: '15559876543',
        message: 'Hello from unconnected spa',
      }),
    });

    assert.equal(resSend.status, 403);
    const bodySend = await resSend.json();
    assert.equal(bodySend.error?.code, 'WHATSAPP_CONNECTION_NOT_CONFIGURED');
  });

  await t.test('4. Business A cannot send through Business B credentials', async () => {
    // Resolve credentials strictly for Business A context
    const credsA = await resolveBusinessWhatsAppCredentials(BIZ_A_ID, 'test');
    assert.equal(credsA.phoneNumberId, phoneA);
    assert.equal(credsA.wabaId, wabaA);
    assert.equal(credsA.accessToken, tokenA);

    // Attempting to resolve credentials for Business B context gives B's credentials to B
    const credsB = await resolveBusinessWhatsAppCredentials(BIZ_B_ID, 'test');
    assert.equal(credsB.phoneNumberId, phoneB);
    assert.notEqual(credsA.accessToken, credsB.accessToken);
  });

  await t.test('5. Existing initial-spa compatibility works ONLY for initial business UUID', async () => {
    // Initial spa without DB connection falls back safely to legacy environment variables
    const initialCreds = await resolveBusinessWhatsAppCredentials(INITIAL_BIZ_ID, 'test');
    assert.ok(initialCreds.phoneNumberId, 'Initial business should resolve fallback phone ID');
    assert.ok(initialCreds.wabaId, 'Initial business should resolve fallback WABA ID');

    // Any other business without DB connection throws WHATSAPP_CONNECTION_NOT_CONFIGURED
    await assert.rejects(
      async () => {
        await resolveBusinessWhatsAppCredentials(BIZ_NO_WABA_ID, 'test');
      },
      (err: any) => {
        return err.code === 'WHATSAPP_CONNECTION_NOT_CONFIGURED' || (err.message && err.message.includes('not configured'));
      }
    );
  });

  await t.test('6. Webhook tenant routing isolates events by registered phone number', async () => {
    // Create messages for A and B with unique provider message IDs
    const runNonce = Date.now().toString(36) + Math.random().toString(36).substring(2, 6);
    const wamidA = `wamid_msg_a_${runNonce}`;
    const wamidB = `wamid_msg_b_${runNonce}`;

    const now = new Date().toISOString();
    const msgA = await messageStore.upsert({
      id: `msg_a_${runNonce}`,
      campaignId: `camp_a_${runNonce}`,
      localCustomerId: 'cust_a_1',
      recipientName: 'Jane A',
      normalizedPhone: '15551234567',
      status: 'sent',
      providerMessageId: wamidA,
      businessId: BIZ_A_ID,
      createdAt: now,
      updatedAt: now,
    });

    const msgB = await messageStore.upsert({
      id: `msg_b_${runNonce}`,
      campaignId: `camp_b_${runNonce}`,
      localCustomerId: 'cust_b_1',
      recipientName: 'Bob B',
      normalizedPhone: '15559876543',
      status: 'sent',
      providerMessageId: wamidB,
      businessId: BIZ_B_ID,
      createdAt: now,
      updatedAt: now,
    });

    // 1. Webhook for Business A's phone number
    const payloadA = {
      object: 'whatsapp_business_account',
      entry: [
        {
          id: wabaA,
          changes: [
            {
              value: {
                messaging_product: 'whatsapp',
                metadata: {
                  display_phone_number: '15551111111',
                  phone_number_id: phoneA,
                },
                statuses: [
                  {
                    id: wamidA,
                    status: 'delivered' as any,
                    timestamp: `${Math.floor(Date.now() / 1000)}`,
                    recipient_id: '15551234567',
                  },
                ],
              },
              field: 'messages',
            },
          ],
        },
      ],
    };

    await WebhookService.processWebhookPayload(payloadA);

    const updatedA = await messageStore.get(msgA.id, BIZ_A_ID);
    assert.equal(updatedA?.status, 'delivered');

    // Verify Business B's message was untouched
    const untouchedB = await messageStore.get(msgB.id, BIZ_B_ID);
    assert.equal(untouchedB?.status, 'sent');

    // 2. Webhook for an unknown phone number drops safely without mutating messages
    const payloadUnknown = {
      object: 'whatsapp_business_account',
      entry: [
        {
          id: 'waba_unknown',
          changes: [
            {
              value: {
                messaging_product: 'whatsapp',
                metadata: {
                  display_phone_number: '19999999999',
                  phone_number_id: 'phone_unknown_9999',
                },
                statuses: [
                  {
                    id: wamidA,
                    status: 'failed' as any,
                    timestamp: `${Math.floor(Date.now() / 1000)}`,
                    recipient_id: '15551234567',
                  },
                ],
              },
              field: 'messages',
            },
          ],
        },
      ],
    };

    await WebhookService.processWebhookPayload(payloadUnknown);

    // Verify message A is still 'delivered' and was NOT mutated by the unknown phone webhook
    const stillA = await messageStore.get(msgA.id, BIZ_A_ID);
    assert.equal(stillA?.status, 'delivered');
  });

  await t.test('7. Webhook STOP opt-outs stay within the target business', async () => {
    const runNonce = Date.now().toString(36) + Math.random().toString(36).substring(2, 6);
    const optedOutPhone = '15553334444';
    const stopMsgId = `wamid_stop_${runNonce}`;

    // Inbound STOP message arriving at Business A's phone number
    const stopPayload = {
      object: 'whatsapp_business_account',
      entry: [
        {
          id: wabaA,
          changes: [
            {
              value: {
                messaging_product: 'whatsapp',
                metadata: {
                  display_phone_number: '15551111111',
                  phone_number_id: phoneA,
                },
                messages: [
                  {
                    from: optedOutPhone,
                    id: stopMsgId,
                    timestamp: `${Math.floor(Date.now() / 1000)}`,
                    text: { body: 'STOP' },
                    type: 'text',
                  },
                ],
              },
              field: 'messages',
            },
          ],
        },
      ],
    };

    await WebhookService.processWebhookPayload(stopPayload);

    // Business A should have opted out the recipient
    const consentA = await consentStore.getConsent(optedOutPhone, 'marketing', BIZ_A_ID);
    assert.equal(consentA?.status, 'opted_out');

    // Business B should NOT have the recipient opted out
    const consentB = await consentStore.getConsent(optedOutPhone, 'marketing', BIZ_B_ID);
    assert.equal(consentB, undefined);
  });
});
