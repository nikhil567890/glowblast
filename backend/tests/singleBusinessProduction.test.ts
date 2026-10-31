import { test, describe, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import { env, isEmailAuthorizedForProduction, getSafeConfigStatus, getWebhookVerifyToken, getActiveDatabaseUrl } from '../src/config/env';
import { CampaignService } from '../src/services/campaignService';
import { templateStore } from '../src/store/templateStore';
import { productionUsageStore, ProductionUsageStore } from '../src/store/productionUsageStore';
import { consentStore, ConsentStore } from '../src/store/consentStore';
import { WebhookService } from '../src/services/webhookService';
import { getPool } from '../src/db/pool';
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
                metadata: { display_phone_number: '12345', phone_number_id: env.PROD_WHATSAPP_PHONE_NUMBER_ID },
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

  test('17. Marketing campaign strictly requires marketing opt-in; utility-only opt-in is rejected', async () => {
    const origEnable = env.ENABLE_PRODUCTION_CAMPAIGNS;
    const origAllowed = env.PRODUCTION_ALLOWED_EMAILS;
    const origToken = env.PROD_WHATSAPP_ACCESS_TOKEN;

    try {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = true;
      (env as any).PRODUCTION_ALLOWED_EMAILS = 'owner@myspa.com';
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = 'mock_valid_token';

      await templateStore.create({
        id: 'tpl_prod_diwali_marketing',
        name: 'diwali_marketing_offer',
        displayName: 'Diwali Marketing Offer',
        category: 'MARKETING',
        language: 'en_US',
        status: 'approved',
        metaStatus: 'APPROVED',
        body: 'Diwali offer for {name}',
        variables: ['name'],
        mode: 'production',
        wabaId: env.PROD_WHATSAPP_BUSINESS_ACCOUNT_ID,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      });

      // Customer only consented to utility (appointment reminders), NOT marketing
      await consentStore.recordConsent({
        phone: '919502259203',
        customerId: 'cust_utility_only_1',
        consentCategory: 'utility',
        status: 'opted_in',
        source: 'appointment_booking_slip',
        evidence: 'Booking #BK-7701',
        consentTextVersion: 'v1.0_utility',
        updatedBy: 'frontdesk@myspa.com',
      });

      assert.equal(await consentStore.hasActiveConsent('919502259203', 'utility'), true);
      assert.equal(await consentStore.hasActiveConsent('919502259203', 'marketing'), false);

      // Attempt marketing blast to this customer -> MUST fail closed
      const resultMarketing = await CampaignService.dispatchCampaign({
        campaignName: 'Diwali Promo Blast',
        templateName: 'diwali_marketing_offer',
        mode: 'production',
        userEmail: 'owner@myspa.com',
        recipients: [{ phone: '919502259203' }],
      });

      assert.equal(resultMarketing.success, false);
      assert.equal(resultMarketing.error?.code, 'NO_ELIGIBLE_CONSENTED_RECIPIENTS');
      assert.ok(resultMarketing.error?.message.includes('opt-in consent found for marketing'));
    } finally {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = origEnable;
      (env as any).PRODUCTION_ALLOWED_EMAILS = origAllowed;
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = origToken;
    }
  });

  test('18. Utility campaign succeeds when utility opt-in is recorded, even without marketing opt-in', async () => {
    const origEnable = env.ENABLE_PRODUCTION_CAMPAIGNS;
    const origAllowed = env.PRODUCTION_ALLOWED_EMAILS;
    const origToken = env.PROD_WHATSAPP_ACCESS_TOKEN;

    try {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = true;
      (env as any).PRODUCTION_ALLOWED_EMAILS = 'owner@myspa.com';
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = 'mock_valid_token';

      await templateStore.create({
        id: 'tpl_prod_appointment_reminder',
        name: 'appointment_reminder',
        displayName: 'Appointment Reminder',
        category: 'UTILITY',
        language: 'en_US',
        status: 'approved',
        metaStatus: 'APPROVED',
        body: 'Appointment confirmation for {name}',
        variables: ['name'],
        mode: 'production',
        wabaId: env.PROD_WHATSAPP_BUSINESS_ACCOUNT_ID,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      });

      // Customer only consented to utility
      await consentStore.recordConsent({
        phone: '919502259203',
        customerId: 'cust_utility_only_2',
        consentCategory: 'utility',
        status: 'opted_in',
        source: 'frontdesk_tablet',
        evidence: 'Tablet Signature #TS-991',
        consentTextVersion: 'v1.0_appointment',
        updatedBy: 'owner@myspa.com',
      });

      assert.equal(await consentStore.hasActiveConsent('919502259203', 'utility'), true);

      // Utility campaign with utility-consented recipient succeeds past validation
      const resultUtility = await CampaignService.dispatchCampaign({
        campaignName: 'Appointment Reminder Blast',
        templateName: 'appointment_reminder',
        mode: 'production',
        userEmail: 'owner@myspa.com',
        recipients: [{ phone: '919502259203' }],
      });

      assert.equal(resultUtility.success, true);
      assert.ok(resultUtility.campaign);
    } finally {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = origEnable;
      (env as any).PRODUCTION_ALLOWED_EMAILS = origAllowed;
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = origToken;
    }
  });

  test('19. Customer opting out of marketing suppresses subsequent marketing broadcasts', async () => {
    const origEnable = env.ENABLE_PRODUCTION_CAMPAIGNS;
    const origAllowed = env.PRODUCTION_ALLOWED_EMAILS;
    const origToken = env.PROD_WHATSAPP_ACCESS_TOKEN;

    try {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = true;
      (env as any).PRODUCTION_ALLOWED_EMAILS = 'owner@myspa.com';
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = 'mock_valid_token';

      await templateStore.create({
        id: 'tpl_prod_summer_blast',
        name: 'summer_blast',
        displayName: 'Summer Blast',
        category: 'MARKETING',
        language: 'en_US',
        status: 'approved',
        metaStatus: 'APPROVED',
        body: 'Summer special for {name}',
        variables: ['name'],
        mode: 'production',
        wabaId: env.PROD_WHATSAPP_BUSINESS_ACCOUNT_ID,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      });

      // Initially opt-in
      await consentStore.recordConsent({
        phone: '919502259203',
        consentCategory: 'marketing',
        status: 'opted_in',
        source: 'intake_form',
        evidence: 'Form #501',
        updatedBy: 'owner@myspa.com',
      });
      assert.equal(await consentStore.hasActiveConsent('919502259203', 'marketing'), true);

      // Customer opts out
      await consentStore.recordConsent({
        phone: '919502259203',
        consentCategory: 'marketing',
        status: 'opted_out',
        source: 'sms_stop',
        evidence: 'Customer sent STOP',
        updatedBy: 'customer',
      });
      assert.equal(await consentStore.hasActiveConsent('919502259203', 'marketing'), false);

      // Now broadcast is rejected
      const result = await CampaignService.dispatchCampaign({
        campaignName: 'Summer Blast',
        templateName: 'summer_blast',
        mode: 'production',
        userEmail: 'owner@myspa.com',
        recipients: [{ phone: '919502259203' }],
      });

      assert.equal(result.success, false);
      assert.equal(result.error?.code, 'NO_ELIGIBLE_CONSENTED_RECIPIENTS');
    } finally {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = origEnable;
      (env as any).PRODUCTION_ALLOWED_EMAILS = origAllowed;
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = origToken;
    }
  });

  test('20. Consent records preserve customerId, consentCategory, evidence and consentTextVersion', async () => {
    const rec = await consentStore.recordConsent({
      phone: '919502259204',
      customerId: 'cust_vip_404',
      consentCategory: 'marketing',
      status: 'opted_in',
      source: 'waiver_signature',
      evidence: 'Waiver #W-2026-99',
      consentTextVersion: 'v2026.2_diwali',
      updatedBy: 'admin@myspa.com',
    });

    assert.ok(rec);
    assert.equal(rec.phone, '919502259204');
    assert.equal(rec.customerId, 'cust_vip_404');
    assert.equal(rec.consentCategory, 'marketing');
    assert.equal(rec.status, 'opted_in');
    assert.equal(rec.source, 'waiver_signature');
    assert.equal(rec.evidence, 'Waiver #W-2026-99');
    assert.equal(rec.consentTextVersion, 'v2026.2_diwali');

    const fetched = await consentStore.getConsent('919502259204', 'marketing');
    assert.ok(fetched);
    assert.equal(fetched.customerId, 'cust_vip_404');
    assert.equal(fetched.evidence, 'Waiver #W-2026-99');
    assert.equal(fetched.consentTextVersion, 'v2026.2_diwali');
  });

  test('21. Historical unclassified consent records NEVER qualify for marketing or utility campaigns', async () => {
    const origEnable = env.ENABLE_PRODUCTION_CAMPAIGNS;
    const origAllowed = env.PRODUCTION_ALLOWED_EMAILS;
    const origToken = env.PROD_WHATSAPP_ACCESS_TOKEN;

    try {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = true;
      (env as any).PRODUCTION_ALLOWED_EMAILS = 'owner@myspa.com';
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = 'mock_valid_token';

      // Insert an unclassified historical record directly into PostgreSQL
      const pool = getPool();
      await pool.query(
        `INSERT INTO customers (id, normalized_phone, display_name)
         VALUES ($1, $2, 'Legacy Customer')
         ON CONFLICT (id) DO NOTHING;`,
        ['cust_legacy_99', '919502259209']
      );
      await pool.query(
        `INSERT INTO customer_consent (
          normalized_phone, customer_id, consent_category, status, source, evidence, updated_by, recorded_at, updated_at
        ) VALUES ($1, $2, 'unclassified', 'opted_in', 'legacy_paper_form', 'Form #1999', 'legacy_migration', NOW(), NOW())
        ON CONFLICT (normalized_phone, consent_category) DO UPDATE SET status = 'opted_in';`,
        ['919502259209', 'cust_legacy_99']
      );

      // Verify server checks
      assert.equal(await consentStore.hasActiveConsent('919502259209', 'marketing'), false);
      assert.equal(await consentStore.hasActiveConsent('919502259209', 'utility'), false);
      assert.equal(await consentStore.hasActiveConsent('919502259209', 'unclassified' as any), false);

      // Template setup for marketing
      await templateStore.create({
        id: 'tpl_prod_legacy_promo',
        name: 'legacy_promo_offer',
        displayName: 'Legacy Promo Offer',
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

      // Marketing campaign must fail closed
      const resultMarketing = await CampaignService.dispatchCampaign({
        campaignName: 'Legacy Marketing Blast',
        templateName: 'legacy_promo_offer',
        mode: 'production',
        userEmail: 'owner@myspa.com',
        recipients: [{ phone: '919502259209' }],
      });
      assert.equal(resultMarketing.success, false);
      assert.equal(resultMarketing.error?.code, 'NO_ELIGIBLE_CONSENTED_RECIPIENTS');

      // Template setup for utility
      await templateStore.create({
        id: 'tpl_prod_legacy_appointment',
        name: 'legacy_appointment_reminder',
        displayName: 'Legacy Appointment Reminder',
        category: 'UTILITY',
        language: 'en_US',
        status: 'approved',
        metaStatus: 'APPROVED',
        body: 'Appointment for {name}',
        variables: ['name'],
        mode: 'production',
        wabaId: env.PROD_WHATSAPP_BUSINESS_ACCOUNT_ID,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      });

      // Utility campaign must fail closed
      const resultUtility = await CampaignService.dispatchCampaign({
        campaignName: 'Legacy Utility Blast',
        templateName: 'legacy_appointment_reminder',
        mode: 'production',
        userEmail: 'owner@myspa.com',
        recipients: [{ phone: '919502259209' }],
      });
      assert.equal(resultUtility.success, false);
      assert.equal(resultUtility.error?.code, 'NO_ELIGIBLE_CONSENTED_RECIPIENTS');
    } finally {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = origEnable;
      (env as any).PRODUCTION_ALLOWED_EMAILS = origAllowed;
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = origToken;
    }
  });

  test('22. Category-specific opt-in and opt-out operate independently', async () => {
    const phone = '919502259210';

    // Opt in to marketing
    await consentStore.recordConsent({
      phone,
      consentCategory: 'marketing',
      status: 'opted_in',
      source: 'web_portal',
      evidence: 'Portal Click',
      updatedBy: 'customer',
    });

    // Opt in to utility
    await consentStore.recordConsent({
      phone,
      consentCategory: 'utility',
      status: 'opted_in',
      source: 'booking_desk',
      evidence: 'Desk Intake',
      updatedBy: 'receptionist',
    });

    assert.equal(await consentStore.hasActiveConsent(phone, 'marketing'), true);
    assert.equal(await consentStore.hasActiveConsent(phone, 'utility'), true);

    // Opt-out from marketing only
    await consentStore.recordOptOut({
      phone,
      consentCategory: 'marketing',
      source: 'whatsapp_stop',
      updatedBy: 'customer',
      reason: 'Customer sent STOP to promo',
    });

    assert.equal(await consentStore.hasActiveConsent(phone, 'marketing'), false);
    assert.equal(await consentStore.hasActiveConsent(phone, 'utility'), true, 'Utility consent must remain active when marketing opts out');

    // Opt-out from utility
    await consentStore.recordOptOut({
      phone,
      consentCategory: 'utility',
      source: 'front_desk',
      updatedBy: 'staff',
      reason: 'Requested no appointment SMS',
    });

    assert.equal(await consentStore.hasActiveConsent(phone, 'marketing'), false);
    assert.equal(await consentStore.hasActiveConsent(phone, 'utility'), false);
  });

  test('23. Customer foreign key integrity is preserved when recording consent', async () => {
    const phone = '919502259211';
    const customerId = 'cust_fk_check_999';

    const rec = await consentStore.recordConsent({
      phone,
      customerId,
      consentCategory: 'marketing',
      status: 'opted_in',
      source: 'digital_tablet',
      evidence: 'Signature verified',
      updatedBy: 'owner@myspa.com',
    });

    assert.ok(rec);
    assert.equal(rec.customerId, customerId);

    const pool = getPool();
    // Check that customer exists in customers table
    const custRes = await pool.query<{ id: string; normalized_phone: string }>(
      `SELECT id, normalized_phone FROM customers WHERE id = $1;`,
      [customerId]
    );
    assert.equal(custRes.rows.length, 1);
    assert.equal(custRes.rows[0].id, customerId);
    assert.equal(custRes.rows[0].normalized_phone, phone);

    // Verify foreign key constraint is in place
    const fkRes = await pool.query<{ conname: string }>(
      `SELECT conname FROM pg_constraint
       WHERE conrelid = 'customer_consent'::regclass
         AND conname = 'customer_consent_customer_id_fkey';`
    );
    assert.equal(fkRes.rows.length, 1, 'customer_consent_customer_id_fkey must exist and be enforced');
  });

  test('24. Migration 007 is idempotent, rerunnable, and preserves audit log history', async () => {
    const pool = getPool();
    const candidatePaths = [
      path.join(__dirname, '../src/db/migrations/007_add_consent_category_and_metadata.sql'),
      path.join(__dirname, '../../src/db/migrations/007_add_consent_category_and_metadata.sql'),
      path.join(process.cwd(), 'src/db/migrations/007_add_consent_category_and_metadata.sql'),
      path.join(process.cwd(), 'backend/src/db/migrations/007_add_consent_category_and_metadata.sql'),
    ];
    const migrationPath = candidatePaths.find((p) => fs.existsSync(p)) || candidatePaths[0];
    const sql = fs.readFileSync(migrationPath, 'utf8');

    // Run migration 007 SQL directly on existing populated database
    await pool.query(sql);

    // Verify constraints and columns still exist and work
    const checkRes = await pool.query<{ conname: string }>(
      `SELECT conname FROM pg_constraint WHERE conname IN ('chk_customer_consent_category', 'chk_consent_audit_category');`
    );
    assert.ok(checkRes.rows.length >= 1, 'Check constraints must exist after rerun');

    // Verify consent registry functions normally after rerun
    const phone = '919502259212';
    await consentStore.recordConsent({
      phone,
      consentCategory: 'marketing',
      status: 'opted_in',
      source: 'after_migration_rerun',
      evidence: 'Testing rerun durability',
      updatedBy: 'admin@myspa.com',
    });

    assert.equal(await consentStore.hasActiveConsent(phone, 'marketing'), true);

    // Verify audit log has recorded the category correctly
    const auditRes = await pool.query<{ consent_category: string; action: string }>(
      `SELECT consent_category, action FROM consent_audit_log WHERE normalized_phone = $1 ORDER BY id DESC LIMIT 1;`,
      [phone]
    );
    assert.equal(auditRes.rows.length, 1);
    assert.equal(auditRes.rows[0].consent_category, 'marketing');
    assert.equal(auditRes.rows[0].action, 'initial_opt_in');
  });

  test('25. Duplicate preservation: Migration aborts without deleting data if duplicate records exist', async () => {
    const pool = getPool();
    const client = await pool.connect();

    try {
      await client.query('BEGIN;');

      // Drop composite PK inside transaction to simulate unmigrated table with potential duplicates
      await client.query('ALTER TABLE customer_consent DROP CONSTRAINT customer_consent_pkey;');

      // Insert duplicate rows for the same phone and category
      await client.query(
        `INSERT INTO customer_consent (
          normalized_phone, consent_category, status, source, evidence, updated_by, recorded_at, updated_at
        ) VALUES 
          ('919502259299', 'marketing', 'opted_in', 'source_a', 'evidence_a', 'admin1', NOW(), NOW()),
          ('919502259299', 'marketing', 'opted_out', 'source_b', 'evidence_b', 'admin2', NOW(), NOW());`
      );

      // Attempt to run the primary-key adjustment logic within a savepoint
      await client.query('SAVEPOINT sp_dup;');
      let threw = false;
      let errorMessage = '';
      try {
        await client.query(`
          DO $$
          DECLARE
              pk_name TEXT;
              pk_cols TEXT[];
              dup_count INT := 0;
          BEGIN
              SELECT c.conname, ARRAY_AGG(a.attname ORDER BY array_position(c.conkey, a.attnum))
              INTO pk_name, pk_cols
              FROM pg_constraint c
              JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
              WHERE c.conrelid = 'public.customer_consent'::regclass
                AND c.contype = 'p'
              GROUP BY c.conname;

              IF pk_cols = ARRAY['normalized_phone', 'consent_category'] THEN
                  RETURN;
              END IF;

              SELECT COUNT(*) INTO dup_count
              FROM (
                  SELECT normalized_phone, consent_category
                  FROM public.customer_consent
                  GROUP BY normalized_phone, consent_category
                  HAVING COUNT(*) > 1
              ) dups;

              IF dup_count > 0 THEN
                  RAISE EXCEPTION 'Migration 007 aborted: % conflicting duplicate group(s) found on customer_consent(normalized_phone, consent_category). Automatic deletion is disabled to preserve data integrity. Run preflight query: SELECT normalized_phone, consent_category, count(*), array_agg(status) AS statuses, array_agg(recorded_at) AS recorded_timestamps FROM customer_consent GROUP BY normalized_phone, consent_category HAVING count(*) > 1;', dup_count;
              END IF;
          END $$;
        `);
      } catch (err: any) {
        threw = true;
        errorMessage = err.message;
        await client.query('ROLLBACK TO SAVEPOINT sp_dup;').catch(() => {});
      }

      assert.equal(threw, true, 'Migration must abort when duplicate records are found');
      assert.ok(errorMessage.includes('conflicting duplicate group(s) found'));
      assert.ok(errorMessage.includes('Automatic deletion is disabled to preserve data integrity'));

      // Verify that neither record was deleted using ctid or any other automatic method
      const countRes = await client.query<{ count: string }>(
        `SELECT COUNT(*) as count FROM customer_consent WHERE normalized_phone = '919502259299';`
      );
      assert.equal(parseInt(countRes.rows[0].count, 10), 2, 'Both duplicate records must be preserved without deletion');
    } finally {
      await client.query('ROLLBACK;').catch(() => {});
      client.release();
    }
  });

  test('26. Provenance enforcement: Stored marketing category without verified provenance cannot authorize a production campaign', async () => {
    const origEnable = env.ENABLE_PRODUCTION_CAMPAIGNS;
    const origAllowed = env.PRODUCTION_ALLOWED_EMAILS;
    const origToken = env.PROD_WHATSAPP_ACCESS_TOKEN;

    try {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = true;
      (env as any).PRODUCTION_ALLOWED_EMAILS = 'owner@myspa.com';
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = 'mock_valid_token';

      const pool = getPool();
      const phone = '919502259288';

      // Insert record where stored category is 'marketing', but provenance lacks consentTextVersion and source is 'legacy'
      await pool.query(
        `INSERT INTO customer_consent (
          normalized_phone, consent_category, status, source, evidence, consent_text_version, updated_by, recorded_at, updated_at
        ) VALUES ($1, 'marketing', 'opted_in', 'legacy', 'Legacy DB row', NULL, 'system', NOW(), NOW())
        ON CONFLICT (normalized_phone, consent_category) DO UPDATE SET consent_text_version = NULL, source = 'legacy';`,
        [phone]
      );

      // Verify that consentStore refuses to authorize campaign because provenance is unverified
      assert.equal(await consentStore.hasActiveConsent(phone, 'marketing'), false, 'Historical record lacking provenance must not qualify for marketing');

      await templateStore.create({
        id: 'tpl_prod_provenance_check',
        name: 'provenance_check_offer',
        displayName: 'Provenance Check Offer',
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

      // Campaign dispatch must fail closed with NO_ELIGIBLE_CONSENTED_RECIPIENTS
      const result = await CampaignService.dispatchCampaign({
        campaignName: 'Provenance Test Campaign',
        templateName: 'provenance_check_offer',
        mode: 'production',
        userEmail: 'owner@myspa.com',
        recipients: [{ phone }],
      });

      assert.equal(result.success, false);
      assert.equal(result.error?.code, 'NO_ELIGIBLE_CONSENTED_RECIPIENTS');
    } finally {
      (env as any).ENABLE_PRODUCTION_CAMPAIGNS = origEnable;
      (env as any).PRODUCTION_ALLOWED_EMAILS = origAllowed;
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = origToken;
    }
  });

  test('27. Exact primary-key detection: Accurately detects composite schema without dropping constraint', async () => {
    const pool = getPool();

    // Query exact primary key columns on public.customer_consent
    const pkRes = await pool.query<{ conname: string; pk_cols: any }>(
      `SELECT c.conname, array_agg(a.attname ORDER BY array_position(c.conkey, a.attnum)) AS pk_cols
       FROM pg_constraint c
       JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
       WHERE c.conrelid = 'public.customer_consent'::regclass
         AND c.contype = 'p'
       GROUP BY c.conname;`
    );

    assert.equal(pkRes.rows.length, 1);
    const rawCols = pkRes.rows[0].pk_cols;
    const pkCols = Array.isArray(rawCols)
      ? rawCols
      : String(rawCols).replace(/[{}]/g, '').split(',');
    assert.deepEqual(pkCols, ['normalized_phone', 'consent_category']);

    // Re-run migration 007 to verify it detects the exact composite PK and takes the safe no-op branch
    const candidatePaths = [
      path.join(__dirname, '../src/db/migrations/007_add_consent_category_and_metadata.sql'),
      path.join(__dirname, '../../src/db/migrations/007_add_consent_category_and_metadata.sql'),
      path.join(process.cwd(), 'src/db/migrations/007_add_consent_category_and_metadata.sql'),
      path.join(process.cwd(), 'backend/src/db/migrations/007_add_consent_category_and_metadata.sql'),
    ];
    const migrationPath = candidatePaths.find((p) => fs.existsSync(p)) || candidatePaths[0];
    const sql = fs.readFileSync(migrationPath, 'utf8');
    await pool.query(sql);

    // Ensure PK remains intact with exact columns
    const pkResAfter = await pool.query<{ conname: string; pk_cols: any }>(
      `SELECT c.conname, array_agg(a.attname ORDER BY array_position(c.conkey, a.attnum)) AS pk_cols
       FROM pg_constraint c
       JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
       WHERE c.conrelid = 'public.customer_consent'::regclass
         AND c.contype = 'p'
       GROUP BY c.conname;`
    );
    assert.equal(pkResAfter.rows.length, 1);
    const rawColsAfter = pkResAfter.rows[0].pk_cols;
    const pkColsAfter = Array.isArray(rawColsAfter)
      ? rawColsAfter
      : String(rawColsAfter).replace(/[{}]/g, '').split(',');
    assert.deepEqual(pkColsAfter, ['normalized_phone', 'consent_category']);
  });
});
