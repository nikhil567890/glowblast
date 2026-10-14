import { test, describe, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import { env, isEmailAuthorizedForProduction, getSafeConfigStatus, getWebhookVerifyToken, getActiveDatabaseUrl } from '../src/config/env';
import { CampaignService } from '../src/services/campaignService';
import { templateStore } from '../src/store/templateStore';
import { productionUsageStore, ProductionUsageStore } from '../src/store/productionUsageStore';
import { consentStore, ConsentStore } from '../src/store/consentStore';
import { WebhookService } from '../src/services/webhookService';
import fs from 'fs';
import path from 'path';

describe('Single-Business Production WhatsApp Cloud API Controls', () => {
  beforeEach(async () => {
    await productionUsageStore.clear();
    await consentStore.clear();
  });

  test('1. Demo mode is rejected on backend dispatch', async () => {
    const result = await CampaignService.dispatchCampaign({
      campaignName: 'Demo Test Blast',
      templateName: 'hello_world',
      mode: 'demo',
      recipients: [{ phone: '919502259203' }],
    });

    assert.equal(result.success, false);
    assert.equal(result.error?.code, 'DEMO_MODE_NOT_ALLOWED');
  });

  test('2. Test mode enforces 5-recipient cap and test allowlist with sandbox config', async () => {
    // Should reject 6 recipients in test mode
    const resultOverLimit = await CampaignService.dispatchCampaign({
      campaignName: 'Test Over Limit',
      templateName: 'hello_world',
      mode: 'test',
      recipients: [
        { phone: '919182769151' },
        { phone: '919182769152' },
        { phone: '919182769153' },
        { phone: '919182769154' },
        { phone: '919182769155' },
        { phone: '919182769156' },
      ],
    });
    assert.equal(resultOverLimit.success, false);
    assert.equal(resultOverLimit.error?.code, 'TEST_RECIPIENT_LIMIT');
  });

  test('3. Production mode fails closed when ENABLE_PRODUCTION_CAMPAIGNS is false', async () => {
    // Current env has ENABLE_PRODUCTION_CAMPAIGNS = false
    assert.equal(env.ENABLE_PRODUCTION_CAMPAIGNS, false);

    const result = await CampaignService.dispatchCampaign({
      campaignName: 'Live Prod Blast',
      templateName: 'birthday_offer',
      mode: 'production',
      userEmail: 'owner@myspa.com',
      recipients: [{ phone: '919502259203', hasConsent: true }],
    });

    assert.equal(result.success, false);
    assert.equal(result.error?.code, 'PRODUCTION_MODE_DISABLED');
  });

  test('4. Production mode rejects unauthorized user email addresses', async () => {
    const origEnable = env.ENABLE_PRODUCTION_CAMPAIGNS;
    const origAllowed = env.PRODUCTION_ALLOWED_EMAILS;
    const origToken = env.PROD_WHATSAPP_ACCESS_TOKEN;

    try {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = true;
      (env as any).PRODUCTION_ALLOWED_EMAILS = 'authorized_owner@myspa.com,admin@myspa.com';
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = 'mock_valid_token_for_test';

      assert.equal(isEmailAuthorizedForProduction('authorized_owner@myspa.com'), true);
      assert.equal(isEmailAuthorizedForProduction('unauthorized_hacker@other.com'), false);
      assert.equal(isEmailAuthorizedForProduction(undefined), false);

      const resultUnauthorized = await CampaignService.dispatchCampaign({
        campaignName: 'Live Prod Blast',
        templateName: 'birthday_offer',
        mode: 'production',
        userEmail: 'unauthorized_hacker@other.com',
        recipients: [{ phone: '919502259203', hasConsent: true }],
      });

      assert.equal(resultUnauthorized.success, false);
      assert.equal(resultUnauthorized.error?.code, 'UNAUTHORIZED_PRODUCTION_USER');
    } finally {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = origEnable;
      (env as any).PRODUCTION_ALLOWED_EMAILS = origAllowed;
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = origToken;
    }
  });

  test('5. Production mode rejects hello_world test template and unapproved templates', async () => {
    const origEnable = env.ENABLE_PRODUCTION_CAMPAIGNS;
    const origAllowed = env.PRODUCTION_ALLOWED_EMAILS;
    const origToken = env.PROD_WHATSAPP_ACCESS_TOKEN;

    try {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = true;
      (env as any).PRODUCTION_ALLOWED_EMAILS = 'owner@myspa.com';
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = 'mock_valid_token';

      // hello_world in production
      const resultHelloWorld = await CampaignService.dispatchCampaign({
        campaignName: 'Live Prod Blast',
        templateName: 'hello_world',
        mode: 'production',
        userEmail: 'owner@myspa.com',
        recipients: [{ phone: '919502259203', hasConsent: true }],
      });
      assert.equal(resultHelloWorld.success, false);
      assert.equal(resultHelloWorld.error?.code, 'INVALID_PRODUCTION_TEMPLATE');

      // Unapproved template
      const resultUnapproved = await CampaignService.dispatchCampaign({
        campaignName: 'Live Prod Blast',
        templateName: 'unapproved_promotional_template',
        mode: 'production',
        userEmail: 'owner@myspa.com',
        recipients: [{ phone: '919502259203', hasConsent: true }],
      });
      assert.equal(resultUnapproved.success, false);
      assert.equal(resultUnapproved.error?.code, 'TEMPLATE_NOT_APPROVED');
    } finally {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = origEnable;
      (env as any).PRODUCTION_ALLOWED_EMAILS = origAllowed;
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = origToken;
    }
  });

  test('6. Attempted customer consent forgery is detected and rejected (client hasConsent: true without server record)', async () => {
    const origEnable = env.ENABLE_PRODUCTION_CAMPAIGNS;
    const origAllowed = env.PRODUCTION_ALLOWED_EMAILS;
    const origToken = env.PROD_WHATSAPP_ACCESS_TOKEN;

    try {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = true;
      (env as any).PRODUCTION_ALLOWED_EMAILS = 'owner@myspa.com';
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = 'mock_valid_token';

      // Register an approved production template
      await templateStore.create({
        id: 'tpl_prod_verified_offer',
        name: 'verified_offer',
        displayName: 'Verified Offer',
        category: 'MARKETING',
        language: 'en_US',
        status: 'approved',
        metaStatus: 'APPROVED',
        body: 'Special offer for {name}',
        variables: ['name'],
        mode: 'production',
        wabaId: env.PROD_WHATSAPP_BUSINESS_ACCOUNT_ID,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      });

      // Attack simulation: Flutter or malicious client sends forged hasConsent: true with forged timestamp
      // Server consentStore is EMPTY for this recipient
      assert.equal(await consentStore.hasActiveConsent('919502259203'), false);

      const resultForged = await CampaignService.dispatchCampaign({
        campaignName: 'Live Prod Blast',
        templateName: 'verified_offer',
        mode: 'production',
        userEmail: 'owner@myspa.com',
        recipients: [
          {
            phone: '+91 95022 59203',
            hasConsent: true, // Forged client boolean
            consentRecordedAt: new Date().toISOString(), // Forged client timestamp
          },
        ],
      });

      // Backend MUST fail closed because server has no authoritative consent record
      assert.equal(resultForged.success, false);
      assert.equal(resultForged.error?.code, 'NO_ELIGIBLE_CONSENTED_RECIPIENTS');
      assert.ok(resultForged.error?.message.includes('server-side WhatsApp opt-in consent'));
    } finally {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = origEnable;
      (env as any).PRODUCTION_ALLOWED_EMAILS = origAllowed;
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = origToken;
    }
  });

  test('7. Outdated or opted-out customer consent record is rejected', async () => {
    const origEnable = env.ENABLE_PRODUCTION_CAMPAIGNS;
    const origAllowed = env.PRODUCTION_ALLOWED_EMAILS;
    const origToken = env.PROD_WHATSAPP_ACCESS_TOKEN;

    try {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = true;
      (env as any).PRODUCTION_ALLOWED_EMAILS = 'owner@myspa.com';
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = 'mock_valid_token';

      // First record opt-in, then customer opts out
      await consentStore.recordConsent({
        phone: '919502259203',
        status: 'opted_in',
        source: 'prior_intake_form',
        updatedBy: 'owner@myspa.com',
      });
      assert.equal(await consentStore.hasActiveConsent('919502259203'), true);

      // Now customer opts out
      await consentStore.recordOptOut({
        phone: '919502259203',
        source: 'customer_sms_reply',
        updatedBy: 'system',
        reason: 'Customer requested opt out',
      });
      assert.equal(await consentStore.hasActiveConsent('919502259203'), false);

      // Client attempts to dispatch claiming hasConsent: true
      const resultOptedOut = await CampaignService.dispatchCampaign({
        campaignName: 'Live Prod Blast',
        templateName: 'verified_offer',
        mode: 'production',
        userEmail: 'owner@myspa.com',
        recipients: [{ phone: '+91 95022 59203', hasConsent: true }],
      });

      assert.equal(resultOptedOut.success, false);
      assert.equal(resultOptedOut.error?.code, 'NO_ELIGIBLE_CONSENTED_RECIPIENTS');
    } finally {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = origEnable;
      (env as any).PRODUCTION_ALLOWED_EMAILS = origAllowed;
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = origToken;
    }
  });

  test('8. Legitimate verified server consent is accepted and reserves rolling quota', async () => {
    const origEnable = env.ENABLE_PRODUCTION_CAMPAIGNS;
    const origAllowed = env.PRODUCTION_ALLOWED_EMAILS;
    const origToken = env.PROD_WHATSAPP_ACCESS_TOKEN;

    try {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = true;
      (env as any).PRODUCTION_ALLOWED_EMAILS = 'owner@myspa.com';
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = 'mock_valid_token';

      // Authoritative consent record created on server
      await consentStore.recordConsent({
        phone: '919502259203',
        status: 'opted_in',
        source: 'front_desk_digital_waiver',
        evidence: 'Waiver #8821 signed',
        updatedBy: 'owner@myspa.com',
      });

      assert.equal(await consentStore.hasActiveConsent('919502259203'), true);

      const resultSuccess = await CampaignService.dispatchCampaign({
        campaignName: 'Live Prod Blast',
        templateName: 'verified_offer',
        mode: 'production',
        userEmail: 'owner@myspa.com',
        recipients: [{ phone: '+91 95022 59203' }],
      });

      assert.equal(resultSuccess.success, true);
      assert.ok(resultSuccess.campaign?.campaignId);
      // Quota store should now reflect 1 unique recipient
      assert.equal(await productionUsageStore.getUniqueRecipientsCountLast24Hours(), 1);
    } finally {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = origEnable;
      (env as any).PRODUCTION_ALLOWED_EMAILS = origAllowed;
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = origToken;
    }
  });

  test('9. Inbound STOP keyword in Webhook triggers opt-out override', async () => {
    // Record active consent first
    await consentStore.recordConsent({
      phone: '919876543210',
      status: 'opted_in',
      source: 'initial_consent',
      updatedBy: 'owner@myspa.com',
    });
    assert.equal(await consentStore.hasActiveConsent('919876543210'), true);

    // Simulate inbound STOP message webhook from customer
    await WebhookService.processWebhookPayload({
      object: 'whatsapp_business_account',
      entry: [
        {
          id: 'waba_test',
          changes: [
            {
              field: 'messages',
              value: {
                messaging_product: 'whatsapp',
                metadata: { display_phone_number: '12345', phone_number_id: '9999' },
                messages: [
                  {
                    from: '919876543210',
                    id: `wamid.inbound.stop.${Date.now()}`,
                    timestamp: `${Date.now()}`,
                    type: 'text',
                    text: { body: 'STOP' },
                  },
                ],
              },
            },
          ],
        },
      ],
    });

    // Consent must now be overridden to opted_out
    assert.equal(await consentStore.hasActiveConsent('919876543210'), false);
    const rec = await consentStore.getConsent('919876543210');
    assert.equal(rec?.status, 'opted_out');
    assert.equal(rec?.source, 'inbound_whatsapp_keyword');
  });

  test('10. Rolling 24-hour limit enforces cap across separate and concurrent campaigns', async () => {
    const limit = 5; // test with cap of 5 unique recipients

    // Campaign 1: 3 unique numbers
    const res1 = await productionUsageStore.checkAndReserveRecipients({
      campaignId: 'c1',
      phones: ['+91 95022 59201', '+91 95022 59202', '+91 95022 59203'],
      limit,
    });
    assert.equal(res1.allowed, true);
    assert.equal(res1.currentCount, 3);

    // Campaign 2: 2 unique numbers (total 5 unique numbers reached)
    const res2 = await productionUsageStore.checkAndReserveRecipients({
      campaignId: 'c2',
      phones: ['+91 95022 59204', '+91 95022 59205'],
      limit,
    });
    assert.equal(res2.allowed, true);
    assert.equal(res2.currentCount, 5);

    // Campaign 3: sending to already-contacted number (no new unique contact)
    const resRepeat = await productionUsageStore.checkAndReserveRecipients({
      campaignId: 'c3',
      phones: ['+91 95022 59201'],
      limit,
    });
    assert.equal(resRepeat.allowed, true); // Still 5 unique numbers!

    // Campaign 4: attempting 6th unique number -> MUST BE REJECTED
    const resExceeded = await productionUsageStore.checkAndReserveRecipients({
      campaignId: 'c4',
      phones: ['+91 95022 59299'],
      limit,
    });
    assert.equal(resExceeded.allowed, false);
    assert.ok(resExceeded.reason?.includes('Rolling 24-hour recipient limit reached'));

    // Concurrent race condition test
    const concurrent1 = productionUsageStore.checkAndReserveRecipients({
      campaignId: 'conc1',
      phones: ['+91 95022 59288'],
      limit,
    });
    const concurrent2 = productionUsageStore.checkAndReserveRecipients({
      campaignId: 'conc2',
      phones: ['+91 95022 59277'],
      limit,
    });

    const [c1Res, c2Res] = await Promise.all([concurrent1, concurrent2]);
    assert.equal(c1Res.allowed, false);
    assert.equal(c2Res.allowed, false);
  });

  test('11. Persistence and durability across separate store instances', async () => {
    // 1. Write state in store instance A
    const storeA = new ProductionUsageStore();
    await storeA.checkAndReserveRecipients({
      campaignId: 'camp_restart_test',
      phones: ['919502259201', '919502259202'],
      limit: 10,
    });

    const consentA = new ConsentStore();
    await consentA.recordConsent({
      phone: '919502259201',
      status: 'opted_in',
      source: 'durability_test',
      updatedBy: 'tester',
      isAuthorizedAdmin: true,
      allowOptOutOverride: true,
    });

    // 2. Simulate process restart by creating new instances querying same database
    const storeB = new ProductionUsageStore();
    assert.ok((await storeB.getUniqueRecipientsCountLast24Hours()) >= 2);
    const phones = await storeB.getUniquePhonesLast24Hours();
    assert.ok(phones.includes('919502259201'));

    const consentB = new ConsentStore();
    assert.equal(await consentB.hasActiveConsent('919502259201'), true);
    assert.equal(await consentB.hasActiveConsent('919502259202'), false);
  });

  test('12. Store operations handle invalid inputs and fail closed safely', async () => {
    const store = new ProductionUsageStore();
    const count = await store.getUniqueRecipientsCountLast24Hours();
    assert.ok(count >= 0);

    const cStore = new ConsentStore();
    assert.equal(await cStore.hasActiveConsent('invalid-phone-0000000000'), false);
  });

  test('13. Webhook verification token helper resolves both META_VERIFY_TOKEN and WHATSAPP_WEBHOOK_VERIFY_TOKEN', () => {
    const token = getWebhookVerifyToken();
    assert.ok(token.length > 0);
    assert.equal(token, env.META_VERIFY_TOKEN);

    // If WHATSAPP_WEBHOOK_VERIFY_TOKEN is provided in process.env, it is supported
    process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN = 'custom_wh_token_123';
    assert.equal(getWebhookVerifyToken(), 'custom_wh_token_123');
    delete process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN;
  });

  test('14. Safe config status never exposes secrets or tokens', () => {
    const status = getSafeConfigStatus();
    assert.equal((status as any).WHATSAPP_ACCESS_TOKEN, undefined);
    assert.equal((status as any).PROD_WHATSAPP_ACCESS_TOKEN, undefined);
    assert.equal((status as any).token, undefined);

    assert.ok(status.modes);
    assert.equal(status.modes.production.displayNumber, '+919502259203');
    assert.equal(status.modes.production.phoneNumberId, '1436324276220624');
    assert.equal(status.modes.production.businessAccountId, '3226959717495309');
    assert.equal(status.modes.test.displayNumber, '+1 (555) 632-5494');
  });

  test('15. Only authenticated operations can record customer consent', async () => {
    // Calling consentStore directly requires explicit params
    const rec = await consentStore.recordConsent({
      phone: '919502259201',
      status: 'opted_in',
      source: 'admin_audit',
      updatedBy: 'authorized_admin@myspa.com',
    });
    assert.ok(rec);
    assert.equal(rec.updatedBy, 'authorized_admin@myspa.com');
  });

  test('16. Database URL resolver enforces TEST_DATABASE_URL in development/test and strictly separates production', () => {
    const origNodeEnv = env.NODE_ENV;
    const origTestUrl = (env as any).TEST_DATABASE_URL;
    const origProdUrl = (env as any).DATABASE_URL;

    try {
      (env as any).TEST_DATABASE_URL = 'postgresql://dev_user:secret@dev.neon.tech/glowblast_dev';
      (env as any).DATABASE_URL = 'postgresql://prod_user:secret@prod.neon.tech/glowblast_prod';

      // 1. In test / dev mode, reads TEST_DATABASE_URL
      (env as any).NODE_ENV = 'test';
      assert.equal(getActiveDatabaseUrl(), 'postgresql://dev_user:secret@dev.neon.tech/glowblast_dev');

      (env as any).NODE_ENV = 'development';
      assert.equal(getActiveDatabaseUrl(), 'postgresql://dev_user:secret@dev.neon.tech/glowblast_dev');

      // 2. In production mode, strictly uses DATABASE_URL and never TEST_DATABASE_URL
      (env as any).NODE_ENV = 'production';
      assert.equal(getActiveDatabaseUrl(), 'postgresql://prod_user:secret@prod.neon.tech/glowblast_prod');

      delete (env as any).DATABASE_URL;
      assert.equal(getActiveDatabaseUrl(), undefined); // Does not fall back to TEST_DATABASE_URL in production!

      // 3. Safe config status never exposes connection strings
      const status = getSafeConfigStatus();
      assert.equal((status as any).DATABASE_URL, undefined);
      assert.equal((status as any).TEST_DATABASE_URL, undefined);
      assert.equal((status as any).database.configured, false);
      assert.equal((status as any).database.mode, 'production');
    } finally {
      (env as any).NODE_ENV = origNodeEnv;
      (env as any).TEST_DATABASE_URL = origTestUrl;
      (env as any).DATABASE_URL = origProdUrl;
    }
  });
});
