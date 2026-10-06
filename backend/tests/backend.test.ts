import { test, describe, beforeEach } from 'node:test';
import assert from 'node:assert';
import { normalizeWhatsAppPhone, maskPhone } from '../src/utils/phone';
import { getSafeConfigStatus, getAuthorizedTestRecipients } from '../src/config/env';
import { CampaignService } from '../src/services/campaignService';
import { campaignStore } from '../src/store/campaignStore';
import { messageStore } from '../src/store/messageStore';
import { WebhookService } from '../src/services/webhookService';
import { templateStore } from '../src/store/templateStore';
import { TemplateService } from '../src/services/templateService';

describe('Phone Normalization & Masking', () => {
  test('normalizeWhatsAppPhone handles Indian 10-digit formats', () => {
    assert.strictEqual(normalizeWhatsAppPhone('9876543210'), '919876543210');
    assert.strictEqual(normalizeWhatsAppPhone('+91 98765 43210'), '919876543210');
    assert.strictEqual(normalizeWhatsAppPhone('+91-9876543210'), '919876543210');
    assert.strictEqual(normalizeWhatsAppPhone('09876543210'), '919876543210');
    assert.strictEqual(normalizeWhatsAppPhone('919876543210'), '919876543210');
  });

  test('normalizeWhatsAppPhone rejects invalid numbers and scientific notation', () => {
    assert.strictEqual(normalizeWhatsAppPhone(''), null);
    assert.strictEqual(normalizeWhatsAppPhone('123'), null);
    assert.strictEqual(normalizeWhatsAppPhone('9.87654E+09'), null);
    assert.strictEqual(normalizeWhatsAppPhone('invalid-phone'), null);
  });

  test('maskPhone masks digits for safe logging', () => {
    assert.strictEqual(maskPhone('919876543210'), '9198****3210');
  });
});

describe('Security & Configuration', () => {
  test('getSafeConfigStatus never leaks access tokens', () => {
    const status = getSafeConfigStatus();
    assert.strictEqual('token' in status, false);
    assert.strictEqual('accessToken' in status, false);
    assert.strictEqual('WHATSAPP_ACCESS_TOKEN' in status, false);
    assert.strictEqual(status.testMode, true);
    assert.strictEqual(status.testRecipientLimit, 5);
  });

  test('getAuthorizedTestRecipients normalizes phone numbers', () => {
    const recipients = getAuthorizedTestRecipients();
    assert.ok(Array.isArray(recipients));
    for (const r of recipients) {
      assert.strictEqual(normalizeWhatsAppPhone(r), r);
    }
  });
});

describe('Test Recipient Limit Enforcement', async () => {
  test('CampaignService rejects campaigns with more than 5 recipients', async () => {
    const sixRecipients = [
      { localCustomerId: '1', name: 'User 1', phone: '9876543210' },
      { localCustomerId: '2', name: 'User 2', phone: '9876543211' },
      { localCustomerId: '3', name: 'User 3', phone: '9876543212' },
      { localCustomerId: '4', name: 'User 4', phone: '9876543213' },
      { localCustomerId: '5', name: 'User 5', phone: '9876543214' },
      { localCustomerId: '6', name: 'User 6', phone: '9876543215' },
    ];

    const result = await CampaignService.dispatchCampaign({
      campaignId: `TEST-LIMIT-${Date.now()}`,
      campaignName: 'Test Over Limit',
      templateName: 'hello_world',
      templateLanguage: 'en_US',
      recipients: sixRecipients,
    });

    assert.strictEqual(result.success, false);
    assert.strictEqual(result.error?.code, 'TEST_RECIPIENT_LIMIT');
  });
});

describe('Campaign Status Computation & Recipient Validation', () => {
  test('Campaign dispatch accepts valid campaign payload and initializes queued state', async () => {
    const uniqueId = `CAMP-INIT-${Date.now()}`;
    const singleRecipient = [
      { localCustomerId: '10', name: 'Tester', phone: '9876543210' },
    ];
    const dispatchRes = await CampaignService.dispatchCampaign({
      campaignId: uniqueId,
      campaignName: 'Status Check Test',
      templateName: 'hello_world',
      templateLanguage: 'en_US',
      recipients: singleRecipient,
    });
    assert.strictEqual(dispatchRes.success, true);
    assert.strictEqual(dispatchRes.campaign?.campaignId, uniqueId);
    assert.strictEqual(dispatchRes.campaign?.total, 1);
    assert.strictEqual(dispatchRes.campaign?.queued, 1);
    assert.strictEqual(dispatchRes.campaign?.accepted, 0);

    const summary = campaignStore.getSummary(uniqueId);
    assert.ok(summary);
    assert.strictEqual(summary.campaignId, uniqueId);
    assert.strictEqual(summary.total, 1);
  });

  test('Campaign status is failed when all recipients fail allowlist check', async () => {
    const uniqueId = `CAMP-FAIL-${Date.now()}`;
    // Use numbers not in allowlist
    const unauthorized = [
      { localCustomerId: 'c1', name: 'Unauth 1', phone: '9999900001' },
      { localCustomerId: 'c2', name: 'Unauth 2', phone: '9999900002' },
    ];

    await CampaignService.dispatchCampaign({
      campaignId: uniqueId,
      campaignName: 'All Fail Test',
      templateName: 'hello_world',
      templateLanguage: 'en_US',
      recipients: unauthorized,
    });

    // Wait for async dispatch loop
    await new Promise((r) => setTimeout(r, 600));

    const summary = campaignStore.getSummary(uniqueId);
    assert.ok(summary);
    // Since all failed, status MUST be 'failed', NEVER 'completed'
    assert.strictEqual(summary.status, 'failed');
    assert.strictEqual(summary.failed, 2);
    assert.strictEqual(summary.accepted, 0);
    assert.strictEqual(summary.sent, 0);

    // Verify error transparency on stored messages
    const camp = campaignStore.get(uniqueId);
    assert.ok(camp);
    for (const msg of camp.messages) {
      assert.strictEqual(msg.status, 'failed');
      assert.strictEqual(msg.errorCode, 403);
      assert.ok(msg.errorMessage?.includes('authorized Meta test allowlist'));
    }
  });

  test('calculateCampaignStatus accurately distinguishes completed, completed_with_errors, and failed', () => {
    const testCampId = `CALC-STATUS-${Date.now()}`;
    const now = new Date().toISOString();

    const m1 = {
      id: `${testCampId}_1`,
      campaignId: testCampId,
      localCustomerId: '1',
      recipientName: 'User 1',
      normalizedPhone: '919876543210',
      status: 'accepted' as const,
      createdAt: now,
      updatedAt: now,
    };
    const m2 = {
      id: `${testCampId}_2`,
      campaignId: testCampId,
      localCustomerId: '2',
      recipientName: 'User 2',
      normalizedPhone: '919876543211',
      status: 'failed' as const,
      errorCode: 403,
      createdAt: now,
      updatedAt: now,
    };

    messageStore.upsert(m1);
    messageStore.upsert(m2);

    campaignStore.create({
      campaignId: testCampId,
      campaignName: 'Mixed Test',
      status: 'processing',
      total: 2,
      queued: 0,
      accepted: 1,
      sent: 0,
      delivered: 0,
      read: 0,
      failed: 1,
      excludedOptOut: 0,
      messages: [m1, m2],
      createdAt: now,
      updatedAt: now,
    });

    const status = campaignStore.calculateCampaignStatus(testCampId);
    assert.strictEqual(status, 'completed_with_errors');

    // If both failed:
    messageStore.updateStatus(m1.id, 'failed');
    const allFailedStatus = campaignStore.calculateCampaignStatus(testCampId);
    assert.strictEqual(allFailedStatus, 'failed');
  });
});

describe('Webhook Status Progression & Idempotency', () => {
  const campId = `WH-TEST-${Date.now()}`;
  const now = new Date().toISOString();
  const providerMsgId = `wamid.TEST_${Date.now()}`;
  const internalMsgId = `${campId}_cust1`;

  beforeEach(() => {
    const msg = {
      id: internalMsgId,
      campaignId: campId,
      localCustomerId: 'cust1',
      recipientName: 'Webhook Tester',
      normalizedPhone: '919182769155',
      status: 'accepted' as const,
      providerMessageId: providerMsgId,
      createdAt: now,
      updatedAt: now,
    };
    messageStore.upsert(msg);

    campaignStore.create({
      campaignId: campId,
      campaignName: 'Webhook Campaign',
      status: 'processing',
      total: 1,
      queued: 0,
      accepted: 1,
      sent: 0,
      delivered: 0,
      read: 0,
      failed: 0,
      excludedOptOut: 0,
      messages: [msg],
      createdAt: now,
      updatedAt: now,
    });
  });

  test('Webhook moves message from accepted to sent, then delivered, then read', () => {
    // 1. Sent webhook
    WebhookService.processWebhookPayload({
      object: 'whatsapp_business_account',
      entry: [
        {
          id: 'WH_ENTRY_1',
          changes: [
            {
              field: 'messages',
              value: {
                messaging_product: 'whatsapp',
                metadata: { display_phone_number: '15556325494', phone_number_id: '123' },
                statuses: [
                  {
                    id: providerMsgId,
                    status: 'sent',
                    timestamp: `${Date.now()}`,
                    recipient_id: '919182769155',
                  },
                ],
              },
            },
          ],
        },
      ],
    });

    let msg = messageStore.getByProviderId(providerMsgId);
    assert.strictEqual(msg?.status, 'sent');
    let summary = campaignStore.getSummary(campId);
    assert.strictEqual(summary?.sent, 1);
    assert.strictEqual(summary?.delivered, 0);

    // 2. Delivered webhook
    WebhookService.processWebhookPayload({
      object: 'whatsapp_business_account',
      entry: [
        {
          id: 'WH_ENTRY_2',
          changes: [
            {
              field: 'messages',
              value: {
                messaging_product: 'whatsapp',
                metadata: { display_phone_number: '15556325494', phone_number_id: '123' },
                statuses: [
                  {
                    id: providerMsgId,
                    status: 'delivered',
                    timestamp: `${Date.now()}`,
                    recipient_id: '919182769155',
                  },
                ],
              },
            },
          ],
        },
      ],
    });

    msg = messageStore.getByProviderId(providerMsgId);
    assert.strictEqual(msg?.status, 'delivered');
    summary = campaignStore.getSummary(campId);
    assert.strictEqual(summary?.delivered, 1);
    assert.strictEqual(summary?.read, 0);

    // 3. Read webhook
    WebhookService.processWebhookPayload({
      object: 'whatsapp_business_account',
      entry: [
        {
          id: 'WH_ENTRY_3',
          changes: [
            {
              field: 'messages',
              value: {
                messaging_product: 'whatsapp',
                metadata: { display_phone_number: '15556325494', phone_number_id: '123' },
                statuses: [
                  {
                    id: providerMsgId,
                    status: 'read',
                    timestamp: `${Date.now()}`,
                    recipient_id: '919182769155',
                  },
                ],
              },
            },
          ],
        },
      ],
    });

    msg = messageStore.getByProviderId(providerMsgId);
    assert.strictEqual(msg?.status, 'read');
    summary = campaignStore.getSummary(campId);
    assert.strictEqual(summary?.read, 1);
  });

  test('Out-of-order webhook does not regress a higher status to a lower status', () => {
    // Set status to read
    messageStore.updateStatus(internalMsgId, 'read', providerMsgId);

    // Delayed 'delivered' webhook arrives
    WebhookService.processWebhookPayload({
      object: 'whatsapp_business_account',
      entry: [
        {
          id: 'WH_DELAYED',
          changes: [
            {
              field: 'messages',
              value: {
                messaging_product: 'whatsapp',
                metadata: { display_phone_number: '15556325494', phone_number_id: '123' },
                statuses: [
                  {
                    id: providerMsgId,
                    status: 'delivered',
                    timestamp: `${Date.now()}`,
                    recipient_id: '919182769155',
                  },
                ],
              },
            },
          ],
        },
      ],
    });

    // Message must REMAIN 'read'
    const msg = messageStore.getByProviderId(providerMsgId);
    assert.strictEqual(msg?.status, 'read');
  });

  test('Duplicate webhook does not corrupt counters', () => {
    // Fire delivered 3 times
    for (let i = 0; i < 3; i++) {
      WebhookService.processWebhookPayload({
        object: 'whatsapp_business_account',
        entry: [
          {
            id: `WH_DUP_${i}`,
            changes: [
              {
                field: 'messages',
                value: {
                  messaging_product: 'whatsapp',
                  metadata: { display_phone_number: '15556325494', phone_number_id: '123' },
                  statuses: [
                    {
                      id: providerMsgId,
                      status: 'delivered',
                      timestamp: `${Date.now()}`,
                      recipient_id: '919182769155',
                    },
                  ],
                },
              },
            ],
          },
        ],
      });
    }

    const summary = campaignStore.getSummary(campId);
    // Count must be exactly 1, not 3
    assert.strictEqual(summary?.delivered, 1);
  });
});

describe('Template Management, Parameter Mapping & Approval Gates', () => {
  test('TemplateService converts named variables to Meta numbered format', () => {
    const localBody = 'Hi {name}, your appointment at {business_name} is confirmed!';
    const numbered = TemplateService.convertToMetaNumberedBody(localBody, ['name', 'business_name']);
    assert.strictEqual(numbered, 'Hi {{1}}, your appointment at {{2}} is confirmed!');

    const mapping = TemplateService.getParameterMapping(['name', 'business_name']);
    assert.deepStrictEqual(mapping, { name: '{{1}}', business_name: '{{2}}' });
  });

  test('TemplateService extracts distinct variable placeholders accurately', () => {
    const body = 'Hello {name}, welcome to {business_name}! Enjoy {discount}% off, {name}!';
    const vars = TemplateService.extractVariables(body);
    assert.deepStrictEqual(vars, ['name', 'business_name', 'discount']);
  });

  test('Pre-seeded hello_world template is approved and custom templates default to draft', () => {
    const helloWorld = templateStore.get('tpl_hello_world');
    assert.ok(helloWorld);
    assert.strictEqual(helloWorld.name, 'hello_world');
    assert.strictEqual(helloWorld.status, 'approved');

    const birthdayOffer = templateStore.get('tpl_birthday');
    assert.ok(birthdayOffer);
    assert.strictEqual(birthdayOffer.name, 'birthday_offer');
    assert.strictEqual(birthdayOffer.status, 'draft');

    const diwaliOffer = templateStore.get('tpl_diwali');
    assert.ok(diwaliOffer);
    assert.strictEqual(diwaliOffer.name, 'diwali_offer');
    assert.strictEqual(diwaliOffer.status, 'draft');
  });

  test('Unapproved or draft templates are blocked from campaign dispatch', async () => {
    // 'tpl_vip_draft' is a draft template
    const draftTpl = templateStore.get('tpl_vip_draft');
    assert.ok(draftTpl);
    assert.strictEqual(draftTpl.status, 'draft');

    const result = await CampaignService.dispatchCampaign({
      campaignId: `TEST-DRAFT-${Date.now()}`,
      campaignName: 'Draft Send Attempt',
      templateId: draftTpl.id,
      templateName: draftTpl.name,
      templateLanguage: draftTpl.language,
      recipients: [{ localCustomerId: 'c1', name: 'Tester', phone: '919182769155' }],
    });

    assert.strictEqual(result.success, false);
    assert.strictEqual(result.error?.code, 'TEMPLATE_NOT_APPROVED');
    assert.ok(result.error?.message?.includes('not connected to an approved WhatsApp template yet'));
  });

  test('Selecting unmapped local template name fails clearly without fallback to hello_world', async () => {
    const result = await CampaignService.dispatchCampaign({
      campaignId: `TEST-UNMAPPED-${Date.now()}`,
      campaignName: 'Unmapped Template Attempt',
      templateName: 'non_existent_meta_template_xyz',
      templateLanguage: 'en_US',
      recipients: [{ localCustomerId: 'c1', name: 'Tester', phone: '919182769155' }],
    });

    assert.strictEqual(result.success, false);
    assert.strictEqual(result.error?.code, 'UNMAPPED_TEMPLATE');
    assert.ok(result.error?.message?.includes('not connected to an approved WhatsApp template yet'));
  });

  test('Template parameter validation catches missing required parameters', () => {
    const tpl = templateStore.get('tpl_birthday');
    assert.ok(tpl);
    const validation = TemplateService.validateTemplateParameters(tpl, {
      name: 'Nikhil',
      // missing business_name
    });

    assert.strictEqual(validation.isValid, false);
    assert.ok(validation.missingVariables.includes('business_name'));
  });

  test('Template parameter validation passes when all required variables are supplied', () => {
    const tpl = templateStore.get('tpl_birthday');
    assert.ok(tpl);
    const validation = TemplateService.validateTemplateParameters(tpl, {
      name: 'Nikhil',
      business_name: 'Glow Spa',
    });

    assert.strictEqual(validation.isValid, true);
    assert.strictEqual(validation.missingVariables.length, 0);
  });

  test('Template preview resolves placeholders correctly', () => {
    const tpl = templateStore.get('tpl_birthday');
    assert.ok(tpl);
    const preview = TemplateService.resolvePreview(tpl, {
      name: 'Nikhil',
      business_name: 'Luxspa',
    });
    assert.strictEqual(
      preview,
      '🎂 Happy Birthday month, Nikhil! Celebrate your special day with our rejuvenating therapy at Luxspa. Enjoy 25% OFF on any 90-minute treatment this month. Reply BOOK to reserve!'
    );
  });

  test('Approved custom template with custom language is dispatched with exact name and language', async () => {
    // Register and approve a custom template with custom language
    const customTpl = templateStore.create({
      id: 'tpl_custom_festive',
      name: 'festive_radiance_custom',
      displayName: 'Festive Radiance Custom',
      category: 'MARKETING',
      language: 'hi',
      status: 'approved',
      metaStatus: 'APPROVED',
      body: 'नमस्ते {name}',
      variables: ['name'],
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });

    const result = await CampaignService.dispatchCampaign({
      campaignId: `TEST-CUSTOM-${Date.now()}`,
      campaignName: 'Custom Template Campaign',
      templateId: customTpl.id,
      templateName: customTpl.name,
      templateLanguage: customTpl.language,
      recipients: [{ localCustomerId: 'c1', name: 'Tester', phone: '919182769155' }],
    });

    assert.strictEqual(result.success, true);
    assert.strictEqual(result.campaign?.messages[0].templateName, 'festive_radiance_custom');
    assert.strictEqual(result.campaign?.messages[0].templateLanguage, 'hi');
  });
});
