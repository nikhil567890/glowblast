import { test, describe } from 'node:test';
import assert from 'node:assert';
import { normalizeWhatsAppPhone, maskPhone } from '../src/utils/phone';
import { getSafeConfigStatus } from '../src/config/env';
import { CampaignService } from '../src/services/campaignService';

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
      campaignId: 'TEST-LIMIT-EXCEEDED',
      campaignName: 'Test Over Limit',
      recipients: sixRecipients,
    });

    assert.strictEqual(result.success, false);
    assert.strictEqual(result.error?.code, 'TEST_RECIPIENT_LIMIT');
  });

  test('Campaign status endpoint returns expected structure', async () => {
    const singleRecipient = [
      { localCustomerId: '10', name: 'Tester', phone: '9876543210' },
    ];
    const dispatchRes = await CampaignService.dispatchCampaign({
      campaignId: 'STATUS-TEST-001',
      campaignName: 'Status Check Test',
      recipients: singleRecipient,
    });
    assert.strictEqual(dispatchRes.success, true);
    assert.strictEqual(dispatchRes.campaign?.campaignId, 'STATUS-TEST-001');
    assert.strictEqual(dispatchRes.campaign?.total, 1);
  });
});

