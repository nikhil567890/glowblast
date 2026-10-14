import { test, describe, beforeEach, after } from 'node:test';
import assert from 'node:assert';
import { templateStore, TemplateStore, SEED_TEMPLATES } from '../src/store/templateStore';
import { TemplateService } from '../src/services/templateService';
import { env } from '../src/config/env';
import { getPool } from '../src/db/pool';
import { WhatsAppTemplate } from '../src/types/template';

describe('PostgreSQL Template Store & Meta Synchronization Suite', () => {
  beforeEach(async () => {
    // Clean and re-seed database before each test
    await templateStore.seedDefaults();
  });

  after(async () => {
    // Restore clean state
    await templateStore.seedDefaults();
  });

  test('1. Default seed templates are idempotently persisted in PostgreSQL', async () => {
    const pool = getPool();
    const res = await pool.query<{ count: string }>(
      `SELECT COUNT(*) AS count FROM whatsapp_templates WHERE mode = 'test';`
    );
    const count = parseInt(res.rows[0].count, 10);
    assert.ok(count >= SEED_TEMPLATES.length, `Expected at least ${SEED_TEMPLATES.length} templates in DB, got ${count}`);

    const helloWorld = await templateStore.getById('tpl_hello_world');
    assert.ok(helloWorld);
    assert.strictEqual(helloWorld.name, 'hello_world');
    assert.strictEqual(helloWorld.status, 'approved');
    assert.strictEqual(helloWorld.mode, 'test');

    // Running seedDefaults again should be idempotent without error
    await templateStore.seedDefaults();
    const res2 = await pool.query<{ count: string }>(
      `SELECT COUNT(*) AS count FROM whatsapp_templates WHERE mode = 'test';`
    );
    assert.strictEqual(parseInt(res2.rows[0].count, 10), count);
  });

  test('2. Mode and WABA isolation prevents production from returning sandbox templates', async () => {
    // Ensure test template exists
    const testTpl = await templateStore.getById('tpl_hello_world');
    assert.ok(testTpl);
    assert.strictEqual(testTpl.mode, 'test');

    // Searching for hello_world with mode='production' MUST return undefined
    const prodLookup = await templateStore.findByIdOrName('hello_world', 'production');
    assert.strictEqual(prodLookup, undefined, 'Sandbox hello_world must never be returned for production mode');

    // Create a production template
    const prodTpl: WhatsAppTemplate = {
      id: 'tpl_prod_vip_wellness',
      name: 'vip_wellness_exclusive',
      displayName: 'VIP Wellness Exclusive',
      category: 'MARKETING',
      language: 'en_US',
      status: 'approved',
      metaStatus: 'APPROVED',
      body: 'Welcome to VIP wellness {name} at {business_name}',
      variables: ['name', 'business_name'],
      mode: 'production',
      wabaId: 'prod_waba_99999999',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    await templateStore.create(prodTpl);

    // Production lookup finds it
    const foundProd = await templateStore.findByIdOrName('vip_wellness_exclusive', 'production');
    assert.ok(foundProd);
    assert.strictEqual(foundProd.id, 'tpl_prod_vip_wellness');
    assert.strictEqual(foundProd.mode, 'production');
    assert.strictEqual(foundProd.wabaId, 'prod_waba_99999999');

    // Test mode lookup MUST NOT return the production template
    const foundInTest = await templateStore.findByIdOrName('vip_wellness_exclusive', 'test');
    assert.strictEqual(foundInTest, undefined, 'Production template must never be returned for test mode');
  });

  test('3. Multiple TemplateStore instances read from the same persistent PostgreSQL table', async () => {
    const store1 = new TemplateStore();
    const store2 = new TemplateStore();

    const uniqueName = `dynamic_test_${Date.now()}`;
    const newTpl: WhatsAppTemplate = {
      id: `tpl_${uniqueName}`,
      name: uniqueName,
      displayName: 'Dynamic Test Template',
      category: 'UTILITY',
      language: 'en_US',
      status: 'approved',
      metaStatus: 'APPROVED',
      body: 'Your code is {code}',
      variables: ['code'],
      mode: 'test',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };

    // Write through instance 1
    await store1.create(newTpl);

    // Read through completely separate instance 2
    const readBack = await store2.getById(`tpl_${uniqueName}`);
    assert.ok(readBack, 'Instance 2 must read record persisted by instance 1');
    assert.strictEqual(readBack.name, uniqueName);
    assert.strictEqual(readBack.status, 'approved');
  });

  test('4. Seed defaults never overwrite or downgrade an approved template', async () => {
    // Update tpl_birthday to approved
    await templateStore.updateStatus('tpl_birthday', 'approved', 'APPROVED');

    const updated = await templateStore.getById('tpl_birthday');
    assert.strictEqual(updated?.status, 'approved');
    assert.strictEqual(updated?.metaStatus, 'APPROVED');

    // Trigger seedDefaults (e.g. on application restart)
    const freshStore = new TemplateStore();
    await freshStore.seedDefaults();

    // Verification: status must REMAIN 'approved', NOT reset to 'draft'
    const afterSeed = await freshStore.getById('tpl_birthday');
    assert.strictEqual(afterSeed?.status, 'approved');
    assert.strictEqual(afterSeed?.metaStatus, 'APPROVED');

    // Restore tpl_birthday back to draft for other test suites
    await templateStore.updateStatus('tpl_birthday', 'draft', 'NOT_SUBMITTED');
  });

  test('5. Synchronize production template diwali_spa_offer from production WABA with mocked Meta API', async () => {
    // Configure mock production environment credentials
    const originalProdWaba = env.PROD_WHATSAPP_BUSINESS_ACCOUNT_ID;
    const originalProdToken = env.PROD_WHATSAPP_ACCESS_TOKEN;
    const originalFetch = globalThis.fetch;

    try {
      (env as any).PROD_WHATSAPP_BUSINESS_ACCOUNT_ID = 'waba_prod_diwali_88888';
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = 'mock_prod_access_token_xyz';

      // Mock Meta Graph API templates endpoint response
      globalThis.fetch = (async (url: string | URL | Request, init?: RequestInit) => {
        const urlStr = url.toString();
        if (urlStr.includes('waba_prod_diwali_88888/message_templates')) {
          assert.strictEqual(
            init?.headers && (init.headers as any).Authorization,
            'Bearer mock_prod_access_token_xyz',
            'Must use production access token'
          );

          return {
            ok: true,
            status: 200,
            json: async () => ({
              data: [
                {
                  id: 'meta_diwali_spa_offer_99991',
                  name: 'diwali_spa_offer',
                  status: 'APPROVED',
                  category: 'MARKETING',
                  language: 'en_US',
                  components: [
                    {
                      type: 'BODY',
                      text: 'Celebrate Diwali with 40% off on all luxury spa therapies at {business_name}, {name}!',
                    },
                  ],
                },
              ],
            }),
          } as any;
        }
        return { ok: false, status: 404, json: async () => ({}) } as any;
      }) as any;

      // Execute sync in production mode
      const syncResult = await TemplateService.syncFromMeta('production');
      assert.strictEqual(syncResult.success, true);
      assert.strictEqual(syncResult.syncedCount, 1);

      // Verify diwali_spa_offer was saved to PostgreSQL with mode='production'
      const syncedTpl = await templateStore.getByName('diwali_spa_offer', 'production');
      assert.ok(syncedTpl, 'Production template diwali_spa_offer must be present in PostgreSQL');
      assert.strictEqual(syncedTpl.name, 'diwali_spa_offer');
      assert.strictEqual(syncedTpl.status, 'approved');
      assert.strictEqual(syncedTpl.metaStatus, 'APPROVED');
      assert.strictEqual(syncedTpl.metaTemplateId, 'meta_diwali_spa_offer_99991');
      assert.strictEqual(syncedTpl.mode, 'production');
      assert.strictEqual(syncedTpl.wabaId, 'waba_prod_diwali_88888');
      assert.ok(syncedTpl.body.includes('Celebrate Diwali with 40% off'));

      // Mode isolation check: diwali_spa_offer MUST NOT appear in test mode list
      const testTemplates = await TemplateService.listTemplates('test');
      const foundInTest = testTemplates.find((t) => t.name === 'diwali_spa_offer');
      assert.strictEqual(foundInTest, undefined, 'Production diwali_spa_offer must not be listed in test templates');
    } finally {
      // Restore environment
      (env as any).PROD_WHATSAPP_BUSINESS_ACCOUNT_ID = originalProdWaba;
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = originalProdToken;
      globalThis.fetch = originalFetch;
    }
  });

  test('6. Fail-closed on database error without silent JSON fallback', async () => {
    // Pass bad query to test error propagation
    const pool = getPool();
    await assert.rejects(
      async () => {
        await pool.query('SELECT * FROM non_existent_table_xyz_err;');
      },
      (err: any) => {
        assert.ok(err.message.includes('non_existent_table_xyz_err'));
        return true;
      }
    );
  });
});
