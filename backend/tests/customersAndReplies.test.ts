import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import { app } from '../src/server';
import { getPool } from '../src/db/pool';
import { env } from '../src/config/env';
import { WebhookService } from '../src/services/webhookService';
import { campaignStore } from '../src/store/campaignStore';
import { messageStore } from '../src/store/messageStore';
import { businessStore } from '../src/store/businessStore';

describe('Bulk Customer Deletion & Verified Reply Analytics Suite', () => {
  const pool = getPool();
  let adminToken: string;
  let server: any;
  let baseUrl: string;

  before(async () => {
    // Set up mock business membership for test admin user
    businessStore.setMockBusiness({
      id: 'a0000000-0000-4000-8000-000000000001',
      slug: 'initial-spa',
      displayName: 'Flagship Spa',
      ownerUserId: 'usr_admin_test',
      timezone: 'Asia/Kolkata',
      isActive: true,
      productionEnabled: true,
      dailyRecipientLimit: 200,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    businessStore.setMockMember({
      id: 'mem_admin_test',
      businessId: 'a0000000-0000-4000-8000-000000000001',
      userId: 'usr_admin_test',
      role: 'owner',
      joinedAt: new Date(),
      updatedAt: new Date(),
    });

    // Generate valid admin token
    adminToken = jwt.sign(
      { sub: 'usr_admin_test', email: 'owner@spa.com', role: 'admin' },
      env.JWT_SECRET,
      { expiresIn: '1h' }
    );

    // Start local server on random port
    await new Promise<void>((resolve) => {
      server = app.listen(0, () => {
        const addr = server.address();
        baseUrl = `http://127.0.0.1:${addr.port}`;
        resolve();
      });
    });

    // Clean test records
    await pool.query("DELETE FROM customers WHERE id LIKE 'test_del_%';");
    await pool.query("DELETE FROM customer_consent WHERE normalized_phone LIKE '91998800%';");
    await pool.query("DELETE FROM consent_audit_log WHERE normalized_phone LIKE '91998800%';");
    await pool.query("DELETE FROM campaign_messages WHERE campaign_id LIKE 'REPLY-TEST-%';");
    await pool.query("DELETE FROM campaigns WHERE campaign_id LIKE 'REPLY-TEST-%';");
  });

  after(async () => {
    businessStore.clearMock();
    if (server) {
      server.close();
    }
    await pool.query("DELETE FROM customers WHERE id LIKE 'test_del_%';");
    await pool.query("DELETE FROM customer_consent WHERE normalized_phone LIKE '91998800%';");
    await pool.query("DELETE FROM consent_audit_log WHERE normalized_phone LIKE '91998800%';");
    await pool.query("DELETE FROM campaign_messages WHERE campaign_id LIKE 'REPLY-TEST-%';");
    await pool.query("DELETE FROM campaigns WHERE campaign_id LIKE 'REPLY-TEST-%';");
  });

  test('1. Bulk customer deletion requires authentication', async () => {
    const res = await fetch(`${baseUrl}/api/customers`, {
      method: 'DELETE',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ customerIds: ['test_del_1'] }),
    });

    assert.equal(res.status, 401);
    const body: any = await res.json();
    assert.equal(body.success, false);
    assert.equal(body.error?.code, 'UNAUTHORIZED');
  });

  test('2. Bulk customer deletion safely removes customers while preserving consent and audit history', async () => {
    const custId1 = 'test_del_101';
    const custId2 = 'test_del_102';
    const phone1 = '919988000101';
    const phone2 = '919988000102';

    // Seed customers
    await pool.query(
      `INSERT INTO customers (id, normalized_phone, display_name)
       VALUES ($1, $2, 'Customer 101'), ($3, $4, 'Customer 102')
       ON CONFLICT (id) DO NOTHING;`,
      [custId1, phone1, custId2, phone2]
    );

    // Seed consent records linked to these customers
    await pool.query(
      `INSERT INTO customer_consent (normalized_phone, customer_id, status, consent_category, recorded_at, source, evidence, updated_by)
       VALUES ($1, $2, 'opted_in', 'marketing', NOW(), 'in_person_waiver', 'Waiver #101', 'owner@spa.com'),
              ($3, $4, 'opted_out', 'marketing', NOW(), 'verbal_request', 'In-person request #102', 'owner@spa.com')
       ON CONFLICT (normalized_phone, consent_category) DO NOTHING;`,
      [phone1, custId1, phone2, custId2]
    );

    // Seed audit log
    await pool.query(
      `INSERT INTO consent_audit_log (normalized_phone, action, new_status, source, evidence, actor)
       VALUES ($1, 'initial_opt_in', 'opted_in', 'in_person_waiver', 'Waiver #101', 'owner@spa.com');`,
      [phone1]
    );

    // Call DELETE /api/customers
    const delRes = await fetch(`${baseUrl}/api/customers`, {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${adminToken}`,
      },
      body: JSON.stringify({ customerIds: [custId1, custId2] }),
    });

    assert.equal(delRes.status, 200);
    const delBody: any = await delRes.json();
    assert.equal(delBody.success, true);
    assert.equal(delBody.deletedCount, 2);
    assert.deepEqual(delBody.deletedCustomerIds.sort(), [custId1, custId2].sort());

    // Verify customers are removed from customers table
    const custCheck = await pool.query(
      `SELECT id FROM customers WHERE id IN ($1, $2);`,
      [custId1, custId2]
    );
    assert.equal(custCheck.rows.length, 0, 'Customers table rows must be deleted');

    // Verify consent records are PRESERVED and customer_id is set to NULL via ON DELETE SET NULL
    const consentCheck = await pool.query(
      `SELECT normalized_phone, customer_id, status, evidence
       FROM customer_consent
       WHERE normalized_phone IN ($1, $2)
       ORDER BY normalized_phone ASC;`,
      [phone1, phone2]
    );
    assert.equal(consentCheck.rows.length, 2, 'Consent records must NOT be deleted');
    assert.equal(consentCheck.rows[0].customer_id, null, 'Foreign key must be set to null');
    assert.equal(consentCheck.rows[0].status, 'opted_in');
    assert.equal(consentCheck.rows[0].evidence, 'Waiver #101');
    assert.equal(consentCheck.rows[1].customer_id, null, 'Foreign key must be set to null');
    assert.equal(consentCheck.rows[1].status, 'opted_out');

    // Verify audit log is PRESERVED
    const auditCheck = await pool.query(
      `SELECT normalized_phone, action FROM consent_audit_log WHERE normalized_phone = $1;`,
      [phone1]
    );
    assert.equal(auditCheck.rows.length, 1, 'Audit log must never be deleted');
  });

  test('3. Inbound WhatsApp reply is safely associated to recent campaign recipient and is idempotent', async () => {
    const campaignId = `REPLY-TEST-${Date.now()}`;
    const localCustId = 'test_reply_cust_1';
    const recipientPhone = '919988000555';
    const providerMsgId = `wamid.OUT_${Date.now()}`;
    const inboundReplyId = `wamid.IN_${Date.now()}`;

    // Create campaign and message in store
    await campaignStore.create({
      campaignId,
      campaignName: 'Reply Verification Blast',
      status: 'completed',
      templateName: 'appointment_reminder',
      templateLanguage: 'en_US',
      total: 1,
      queued: 0,
      accepted: 1,
      sent: 1,
      delivered: 1,
      read: 1,
      replied: 0,
      failed: 0,
      excludedOptOut: 0,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      messages: [
        {
          id: `${campaignId}_${localCustId}`,
          campaignId,
          localCustomerId: localCustId,
          recipientName: 'Test Patron',
          normalizedPhone: recipientPhone,
          status: 'read',
          providerMessageId: providerMsgId,
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString(),
        },
      ],
    });

    // Send inbound message webhook payload
    const inboundPayload = {
      object: 'whatsapp_business_account',
      entry: [
        {
          id: 'waba_test',
          changes: [
            {
              field: 'messages',
              value: {
                messaging_product: 'whatsapp',
                metadata: { display_phone_number: '15556325494', phone_number_id: '1272717865934207' },
                contacts: [{ profile: { name: 'Test Patron' }, wa_id: recipientPhone }],
                messages: [
                  {
                    from: recipientPhone,
                    id: inboundReplyId,
                    timestamp: `${Math.floor(Date.now() / 1000)}`,
                    text: { body: 'Please confirm my slot for 3pm!' },
                    type: 'text',
                    context: { id: providerMsgId },
                  },
                ],
              },
            },
          ],
        },
      ],
    };

    // First delivery of inbound reply webhook
    await WebhookService.processWebhookPayload(inboundPayload as any);

    // Verify message has replied_at set
    const updatedMsg = await messageStore.getByProviderId(providerMsgId);
    assert.ok(updatedMsg?.repliedAt, 'Message must have repliedAt timestamp recorded');

    // Verify campaign summary reflects replied = 1
    const summary = await campaignStore.getSummary(campaignId);
    assert.equal(summary?.replied, 1, 'Campaign replied counter must be 1');

    // Send duplicate inbound webhook (same wamid)
    await WebhookService.processWebhookPayload(inboundPayload as any);

    // Verify reply count did NOT inflate
    const summaryAfterDup = await campaignStore.getSummary(campaignId);
    assert.equal(summaryAfterDup?.replied, 1, 'Duplicate webhook must not inflate reply count');
  });
});
