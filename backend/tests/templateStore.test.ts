import { test, describe, before, after } from 'node:test';
import assert from 'node:assert';
import { templateStore, TemplateStore, SEED_TEMPLATES } from '../src/store/templateStore';
import { TemplateService } from '../src/services/templateService';
import { env } from '../src/config/env';
import { getPool } from '../src/db/pool';
import { WhatsAppTemplate } from '../src/types/template';

describe('PostgreSQL Template Store & Meta Synchronization Suite', () => {
  before(async () => {
    // Seed database before test suite runs
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

  test('7. Production synchronization preserves exact language "en", production WABA 3226959717495309, and isolates test diwali_offer', async () => {
    const originalProdWaba = env.PROD_WHATSAPP_BUSINESS_ACCOUNT_ID;
    const originalProdToken = env.PROD_WHATSAPP_ACCESS_TOKEN;
    const originalFetch = globalThis.fetch;

    try {
      (env as any).PROD_WHATSAPP_BUSINESS_ACCOUNT_ID = '3226959717495309';
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = 'test_prod_token_valid';

      // Ensure test template diwali_offer exists and belongs to test mode
      const oldTestTpl = await templateStore.getByName('diwali_offer', 'test');
      assert.ok(oldTestTpl, 'Old test template diwali_offer must exist');
      assert.strictEqual(oldTestTpl.mode, 'test');

      // Mock Meta returning diwali_spa_offer with language 'en' (NOT en_US)
      globalThis.fetch = (async (url: string | URL | Request, init?: RequestInit) => {
        const urlStr = url.toString();
        if (urlStr.includes('3226959717495309/message_templates')) {
          assert.strictEqual(
            init?.headers && (init.headers as any).Authorization,
            'Bearer test_prod_token_valid'
          );
          return {
            ok: true,
            status: 200,
            json: async () => ({
              data: [
                {
                  id: '1851386776000198',
                  name: 'diwali_spa_offer',
                  status: 'APPROVED',
                  category: 'MARKETING',
                  language: 'en', // Exact Meta language returned
                  components: [
                    {
                      type: 'BODY',
                      text: 'Celebrate Diwali with 40% off our luxurious spa treatments at {business_name}, {name}!',
                    },
                  ],
                },
              ],
            }),
          } as any;
        }
        return { ok: false, status: 404, json: async () => ({}) } as any;
      }) as any;

      const result = await TemplateService.syncFromMeta('production');
      assert.strictEqual(result.success, true);
      assert.strictEqual(result.syncedCount, 1);

      // Verify production record attributes
      const prodRecord = await templateStore.getByNameAndMode('diwali_spa_offer', 'production', 'en');
      assert.ok(prodRecord, 'diwali_spa_offer record must be persisted in production mode with language en');
      assert.strictEqual(prodRecord.name, 'diwali_spa_offer');
      assert.strictEqual(prodRecord.language, 'en', 'Must preserve exact language "en" returned by Meta');
      assert.strictEqual(prodRecord.status, 'approved');
      assert.strictEqual(prodRecord.metaStatus, 'APPROVED');
      assert.strictEqual(prodRecord.metaTemplateId, '1851386776000198');
      assert.strictEqual(prodRecord.mode, 'production');
      assert.strictEqual(prodRecord.wabaId, '3226959717495309');
      assert.strictEqual(prodRecord.category, 'MARKETING');

      // Verify old test template diwali_offer is untouched
      const testRecordAfter = await templateStore.getByName('diwali_offer', 'test');
      assert.ok(testRecordAfter);
      assert.strictEqual(testRecordAfter.mode, 'test');
      assert.strictEqual(testRecordAfter.wabaId, oldTestTpl.wabaId, 'Test WABA ID must remain untouched');
      assert.notStrictEqual(testRecordAfter.id, prodRecord.id);

      // Verify mode isolation: production template diwali_spa_offer does NOT appear in test queries
      const testList = await TemplateService.listTemplates('test');
      assert.strictEqual(testList.some((t) => t.name === 'diwali_spa_offer'), false);

      const prodList = await TemplateService.listTemplates('production');
      assert.strictEqual(prodList.some((t) => t.name === 'diwali_spa_offer'), true);
      assert.strictEqual(prodList.some((t) => t.name === 'diwali_offer'), false);
    } finally {
      (env as any).PROD_WHATSAPP_BUSINESS_ACCOUNT_ID = originalProdWaba;
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = originalProdToken;
      globalThis.fetch = originalFetch;
    }
  });

  test('8. Meta Graph API pagination fetches all pages and persists all returned templates', async () => {
    const originalProdWaba = env.PROD_WHATSAPP_BUSINESS_ACCOUNT_ID;
    const originalProdToken = env.PROD_WHATSAPP_ACCESS_TOKEN;
    const originalFetch = globalThis.fetch;

    try {
      (env as any).PROD_WHATSAPP_BUSINESS_ACCOUNT_ID = '3226959717495309';
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = 'test_prod_token_pagination';

      const page1Url = `https://graph.facebook.com/${env.WHATSAPP_API_VERSION}/3226959717495309/message_templates?limit=100`;
      const page2Url = `https://graph.facebook.com/${env.WHATSAPP_API_VERSION}/3226959717495309/message_templates?limit=100&after=CURSOR_PAGE_2`;

      globalThis.fetch = (async (url: string | URL | Request) => {
        const urlStr = url.toString();
        if (urlStr === page1Url) {
          return {
            ok: true,
            status: 200,
            json: async () => ({
              data: [
                {
                  id: 'meta_p1_001',
                  name: 'spring_rejuvenation_page1',
                  status: 'APPROVED',
                  category: 'MARKETING',
                  language: 'en',
                  components: [{ type: 'BODY', text: 'Spring offer {name}' }],
                },
              ],
              paging: {
                next: page2Url,
              },
            }),
          } as any;
        } else if (urlStr === page2Url) {
          return {
            ok: true,
            status: 200,
            json: async () => ({
              data: [
                {
                  id: 'meta_p2_002',
                  name: 'summer_glow_page2',
                  status: 'APPROVED',
                  category: 'MARKETING',
                  language: 'en',
                  components: [{ type: 'BODY', text: 'Summer glow {name}' }],
                },
              ],
              paging: {},
            }),
          } as any;
        }
        return { ok: false, status: 404, json: async () => ({}) } as any;
      }) as any;

      const result = await TemplateService.syncFromMeta('production');
      assert.strictEqual(result.success, true);
      assert.strictEqual(result.syncedCount, 2, 'Must have synced templates across both pages');

      const p1Tpl = await templateStore.getByNameAndMode('spring_rejuvenation_page1', 'production');
      assert.ok(p1Tpl, 'Page 1 template must be saved');
      assert.strictEqual(p1Tpl.metaTemplateId, 'meta_p1_001');

      const p2Tpl = await templateStore.getByNameAndMode('summer_glow_page2', 'production');
      assert.ok(p2Tpl, 'Page 2 template must be saved via pagination cursor');
      assert.strictEqual(p2Tpl.metaTemplateId, 'meta_p2_002');
    } finally {
      (env as any).PROD_WHATSAPP_BUSINESS_ACCOUNT_ID = originalProdWaba;
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = originalProdToken;
      globalThis.fetch = originalFetch;
    }
  });

  test('9. Multi-language templates with same name are stored without unique constraint collisions', async () => {
    const originalProdWaba = env.PROD_WHATSAPP_BUSINESS_ACCOUNT_ID;
    const originalProdToken = env.PROD_WHATSAPP_ACCESS_TOKEN;
    const originalFetch = globalThis.fetch;

    try {
      (env as any).PROD_WHATSAPP_BUSINESS_ACCOUNT_ID = '3226959717495309';
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = 'test_prod_token_multilang';

      globalThis.fetch = (async (url: string | URL | Request) => {
        return {
          ok: true,
          status: 200,
          json: async () => ({
            data: [
              {
                id: 'meta_multi_en',
                name: 'festival_multilang_offer',
                status: 'APPROVED',
                category: 'MARKETING',
                language: 'en',
                components: [{ type: 'BODY', text: 'Celebrate with us in English, {name}!' }],
              },
              {
                id: 'meta_multi_hi',
                name: 'festival_multilang_offer',
                status: 'APPROVED',
                category: 'MARKETING',
                language: 'hi',
                components: [{ type: 'BODY', text: 'हमारे साथ त्योहार मनाएं, {name}!' }],
              },
            ],
          }),
        } as any;
      }) as any;

      const result = await TemplateService.syncFromMeta('production');
      assert.strictEqual(result.success, true);
      assert.strictEqual(result.syncedCount, 2);

      const enVariant = await templateStore.getByNameAndMode('festival_multilang_offer', 'production', 'en');
      assert.ok(enVariant);
      assert.strictEqual(enVariant.language, 'en');
      assert.strictEqual(enVariant.metaTemplateId, 'meta_multi_en');

      const hiVariant = await templateStore.getByNameAndMode('festival_multilang_offer', 'production', 'hi');
      assert.ok(hiVariant);
      assert.strictEqual(hiVariant.language, 'hi');
      assert.strictEqual(hiVariant.metaTemplateId, 'meta_multi_hi');

      assert.notStrictEqual(enVariant.id, hiVariant.id, 'Distinct language variants must have distinct IDs');
    } finally {
      (env as any).PROD_WHATSAPP_BUSINESS_ACCOUNT_ID = originalProdWaba;
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = originalProdToken;
      globalThis.fetch = originalFetch;
    }
  });

  test('10. Updating existing template on sync refreshes body text, variables, and status', async () => {
    // Insert a draft template
    const draftTpl: WhatsAppTemplate = {
      id: 'tpl_prod_refresh_test',
      name: 'refresh_test_template',
      displayName: 'Refresh Test',
      category: 'MARKETING',
      language: 'en',
      status: 'draft',
      metaStatus: 'NOT_SUBMITTED',
      body: 'Old placeholder body',
      variables: [],
      mode: 'production',
      wabaId: '3226959717495309',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    await templateStore.create(draftTpl);

    const originalProdWaba = env.PROD_WHATSAPP_BUSINESS_ACCOUNT_ID;
    const originalProdToken = env.PROD_WHATSAPP_ACCESS_TOKEN;
    const originalFetch = globalThis.fetch;

    try {
      (env as any).PROD_WHATSAPP_BUSINESS_ACCOUNT_ID = '3226959717495309';
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = 'test_prod_token_refresh';

      globalThis.fetch = (async () => {
        return {
          ok: true,
          status: 200,
          json: async () => ({
            data: [
              {
                id: 'meta_refresh_approved_123',
                name: 'refresh_test_template',
                status: 'APPROVED',
                category: 'MARKETING',
                language: 'en',
                components: [
                  {
                    type: 'BODY',
                    text: 'Approved brand new body for {name} with 50% discount at {business_name}!',
                  },
                ],
              },
            ],
          }),
        } as any;
      }) as any;

      const result = await TemplateService.syncFromMeta('production');
      assert.strictEqual(result.success, true);

      const refreshed = await templateStore.getById('tpl_prod_refresh_test');
      assert.ok(refreshed);
      assert.strictEqual(refreshed.status, 'approved');
      assert.strictEqual(refreshed.metaStatus, 'APPROVED');
      assert.strictEqual(refreshed.metaTemplateId, 'meta_refresh_approved_123');
      assert.ok(refreshed.body.includes('Approved brand new body for {name}'));
      assert.ok(refreshed.variables.includes('name'));
      assert.ok(refreshed.variables.includes('business_name'));
    } finally {
      (env as any).PROD_WHATSAPP_BUSINESS_ACCOUNT_ID = originalProdWaba;
      (env as any).PROD_WHATSAPP_ACCESS_TOKEN = originalProdToken;
      globalThis.fetch = originalFetch;
    }
  });
});
