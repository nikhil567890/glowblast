import { test, describe, beforeEach, after } from 'node:test';
import assert from 'node:assert';
import jwt from 'jsonwebtoken';
import { AddressInfo } from 'net';
import { app } from '../src/server';
import { env } from '../src/config/env';
import { campaignStore } from '../src/store/campaignStore';
import { messageStore } from '../src/store/messageStore';
import { CampaignService } from '../src/services/campaignService';
import { getPool } from '../src/db/pool';
import { businessStore } from '../src/store/businessStore';

describe('Schema Resilience & Crash Prevention Suite', () => {
  let server: any;
  let baseUrl: string;
  let validToken: string;

  beforeEach(() => {
    businessStore.setMockBusiness({
      id: 'a0000000-0000-4000-8000-000000000001',
      slug: 'initial-spa',
      displayName: 'Flagship Spa',
      ownerUserId: 'usr_schema_test',
      timezone: 'Asia/Kolkata',
      isActive: true,
      productionEnabled: true,
      dailyRecipientLimit: 200,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    businessStore.setMockMember({
      id: 'mem_schema_test',
      businessId: 'a0000000-0000-4000-8000-000000000001',
      userId: 'usr_schema_test',
      role: 'owner',
      joinedAt: new Date(),
      updatedAt: new Date(),
    });

    if (!server) {
      server = app.listen(0);
      server.unref();
      const port = (server.address() as AddressInfo).port;
      baseUrl = `http://127.0.0.1:${port}`;
      validToken = jwt.sign(
        { sub: 'usr_schema_test', email: 'owner@glowblast.com', name: 'Spa Owner' },
        env.JWT_SECRET,
        { expiresIn: '1h' }
      );
    }
  });

  after(async () => {
    businessStore.clearMock();
    if (server) {
      await new Promise<void>((resolve) => {
        if (typeof server.closeAllConnections === 'function') {
          server.closeAllConnections();
        }
        server.close(() => resolve());
      });
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  });

  test('1. CampaignStore.get() falls back gracefully when count_replied does not exist (Error 42703)', async () => {
    const testCampId = `TEST-SCHEMA-CAMP-${Date.now()}`;
    const pool = getPool();

    // Insert campaign record directly
    await pool.query(
      `INSERT INTO campaigns (campaign_id, campaign_name, mode, status, template_name, total_recipients, count_queued)
       VALUES ($1, 'Schema Fallback Test', 'test', 'processing', 'hello_world', 1, 1)
       ON CONFLICT (campaign_id) DO NOTHING;`,
      [testCampId]
    );

    // Temporarily mock pool.query to simulate missing count_replied column (code 42703) on first query
    const originalQuery = pool.query.bind(pool);
    let errorSimulated = false;

    (pool as any).query = async (text: any, params?: any) => {
      const queryStr = typeof text === 'string' ? text : text?.text || '';
      if (!errorSimulated && queryStr.includes('count_replied') && queryStr.includes('FROM campaigns')) {
        errorSimulated = true;
        const err: any = new Error('column "count_replied" does not exist');
        err.code = '42703';
        throw err;
      }
      return originalQuery(text, params);
    };

    try {
      const camp = await campaignStore.get(testCampId);
      assert.ok(camp, 'Campaign should be retrieved via fallback query');
      assert.strictEqual(camp.campaignId, testCampId);
      assert.strictEqual(camp.replied, 0);
      assert.strictEqual(errorSimulated, true, 'Error 42703 should have been simulated and handled');
    } finally {
      (pool as any).query = originalQuery;
      await pool.query('DELETE FROM campaigns WHERE campaign_id = $1;', [testCampId]).catch(() => {});
    }
  });

  test('2. CampaignStore.recalculateAndSaveCampaignStatus() falls back gracefully on missing count_replied (Error 42703)', async () => {
    const testCampId = `TEST-SCHEMA-STATUS-${Date.now()}`;
    const pool = getPool();

    await pool.query(
      `INSERT INTO campaigns (campaign_id, campaign_name, mode, status, template_name, total_recipients, count_queued)
       VALUES ($1, 'Status Update Fallback Test', 'test', 'processing', 'hello_world', 1, 0)
       ON CONFLICT (campaign_id) DO NOTHING;`,
      [testCampId]
    );

    const originalQuery = pool.query.bind(pool);
    let errorSimulated = false;

    (pool as any).query = async (text: any, params?: any) => {
      const queryStr = typeof text === 'string' ? text : text?.text || '';
      if (!errorSimulated && queryStr.includes('count_replied = $8') && queryStr.includes('UPDATE campaigns')) {
        errorSimulated = true;
        const err: any = new Error('column "count_replied" does not exist');
        err.code = '42703';
        throw err;
      }
      return originalQuery(text, params);
    };

    try {
      const updated = await campaignStore.recalculateAndSaveCampaignStatus(testCampId);
      assert.ok(updated, 'Status should be recalculated and saved via fallback');
      assert.strictEqual(updated.status, 'completed');
      assert.strictEqual(errorSimulated, true, 'Error 42703 update should have triggered legacy update');
    } finally {
      (pool as any).query = originalQuery;
      await pool.query('DELETE FROM campaigns WHERE campaign_id = $1;', [testCampId]).catch(() => {});
    }
  });

  test('3. MessageStore.getByCampaignId() falls back gracefully when replied_at does not exist (Error 42703)', async () => {
    const testCampId = `TEST-SCHEMA-MSG-${Date.now()}`;
    const testMsgId = `${testCampId}_cust1`;
    const pool = getPool();

    await pool.query(
      `INSERT INTO campaigns (campaign_id, campaign_name, mode, status, template_name)
       VALUES ($1, 'Message Fallback Test', 'test', 'processing', 'hello_world')
       ON CONFLICT (campaign_id) DO NOTHING;`,
      [testCampId]
    );

    await pool.query(
      `INSERT INTO campaign_messages (id, campaign_id, local_customer_id, recipient_name, normalized_phone, status, created_at, updated_at)
       VALUES ($1, $2, 'cust1', 'Fallback Tester', '919182769155', 'queued', NOW(), NOW())
       ON CONFLICT (id) DO NOTHING;`,
      [testMsgId, testCampId]
    );

    const originalQuery = pool.query.bind(pool);
    let errorSimulated = false;

    (pool as any).query = async (text: any, params?: any) => {
      const queryStr = typeof text === 'string' ? text : text?.text || '';
      if (!errorSimulated && queryStr.includes('replied_at') && queryStr.includes('FROM campaign_messages')) {
        errorSimulated = true;
        const err: any = new Error('column "replied_at" does not exist');
        err.code = '42703';
        throw err;
      }
      return originalQuery(text, params);
    };

    try {
      const msgs = await messageStore.getByCampaignId(testCampId);
      assert.strictEqual(msgs.length, 1);
      assert.strictEqual(msgs[0].id, testMsgId);
      assert.strictEqual(msgs[0].repliedAt, undefined);
      assert.strictEqual(errorSimulated, true);
    } finally {
      (pool as any).query = originalQuery;
      await pool.query('DELETE FROM campaign_messages WHERE campaign_id = $1;', [testCampId]).catch(() => {});
      await pool.query('DELETE FROM campaigns WHERE campaign_id = $1;', [testCampId]).catch(() => {});
    }
  });

  test('4. POST /api/campaigns/send catches database query error and returns HTTP 500 without crashing process', async () => {
    const originalDispatch = CampaignService.dispatchCampaign;

    (CampaignService as any).dispatchCampaign = async () => {
      const err: any = new Error('Simulated catastrophic database failure');
      err.code = 'XX000';
      throw err;
    };

    try {
      const res = await fetch(`${baseUrl}/api/campaigns/send`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${validToken}`,
        },
        body: JSON.stringify({
          campaignName: 'Crash Prevention Test',
          templateName: 'hello_world',
          templateLanguage: 'en_US',
          recipients: [{ phone: '919182769155' }],
        }),
      });

      // Crucial: The server must NOT crash and must return a clean HTTP 500 JSON error
      assert.strictEqual(res.status, 500);
      const data = (await res.json()) as any;
      assert.strictEqual(data.success, false);
      assert.strictEqual(data.error?.code, 'DATABASE_ERROR');
      assert.ok(data.error?.message?.includes('Simulated catastrophic database failure'));
    } finally {
      CampaignService.dispatchCampaign = originalDispatch;
    }
  });

  test('5. GET /api/campaigns/:campaignId returns 500 DATABASE_ERROR on unexpected database error without crashing', async () => {
    const pool = getPool();
    const originalQuery = pool.query.bind(pool);

    (pool as any).query = async (text: any, params?: any) => {
      const queryStr = typeof text === 'string' ? text : text?.text || '';
      if (queryStr.includes('FROM campaigns')) {
        const err: any = new Error('Connection terminated unexpectedly');
        err.code = '08006';
        throw err;
      }
      return originalQuery(text, params);
    };

    try {
      const res = await fetch(`${baseUrl}/api/campaigns/GB-NONEXISTENT-9999`, {
        headers: { Authorization: `Bearer ${validToken}` },
      });
      assert.strictEqual(res.status, 500);
      const data = (await res.json()) as any;
      assert.strictEqual(data.success, false);
      assert.strictEqual(data.error?.code, 'DATABASE_ERROR');
    } finally {
      (pool as any).query = originalQuery;
    }
  });
});
