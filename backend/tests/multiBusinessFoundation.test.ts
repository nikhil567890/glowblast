process.env.NODE_ENV = 'test';
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'fs';
import path from 'path';
import jwt from 'jsonwebtoken';
import { app } from '../src/server';
import { env } from '../src/config/env';
import { requireAuth, requireBusinessMembership } from '../src/middleware/authMiddleware';
import { businessStore } from '../src/store/businessStore';
import { Business, BusinessMember } from '../src/types/business';

test('Multi-Business SaaS Foundation: Phase 1 Test Suite', async (t) => {
  const server = app.listen(0);
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : 0;
  const baseUrl = `http://127.0.0.1:${port}`;

  t.after(() => {
    server.close();
  });

  const testOwnerId = 'usr_owner_phase1_test';
  const testStaffId = 'usr_staff_phase1_test';
  const testAttackerId = 'usr_attacker_phase1_test';

  const ownerToken = jwt.sign(
    { sub: testOwnerId, email: 'owner@flagshipspa.com', name: 'Spa Owner' },
    env.JWT_SECRET,
    { expiresIn: '1h' }
  );

  const staffToken = jwt.sign(
    { sub: testStaffId, email: 'staff@flagshipspa.com', name: 'Spa Staff' },
    env.JWT_SECRET,
    { expiresIn: '1h' }
  );

  const attackerToken = jwt.sign(
    { sub: testAttackerId, email: 'attacker@competitor.com', name: 'Attacker' },
    env.JWT_SECRET,
    { expiresIn: '1h' }
  );

  // --------------------------------------------------------------------------
  // 1. Migration Files Structural & Schema Integrity
  // --------------------------------------------------------------------------
  function resolveDbFile(relPath: string): string {
    const candidates = [
      path.resolve(__dirname, '../src/db', relPath),
      path.resolve(__dirname, '../../src/db', relPath),
      path.resolve(process.cwd(), 'src/db', relPath),
      path.resolve(process.cwd(), 'backend/src/db', relPath),
    ];
    for (const c of candidates) {
      if (fs.existsSync(c)) return c;
    }
    return candidates[0];
  }

  await t.test('1. Migration 009 (Create Businesses) defines expected schema and indexes', () => {
    const migrationPath = resolveDbFile('migrations/009_create_businesses.sql');
    const sql = fs.readFileSync(migrationPath, 'utf8');

    assert.ok(sql.includes('CREATE TABLE IF NOT EXISTS businesses'), 'Must create businesses table');
    assert.ok(sql.includes('id                  UUID PRIMARY KEY'), 'ID must be UUID PRIMARY KEY');
    assert.ok(sql.includes('slug                VARCHAR(63) UNIQUE NOT NULL'), 'Slug must be unique');
    assert.ok(sql.includes('owner_user_id       VARCHAR(64) NOT NULL REFERENCES users(id)'), 'Owner must reference users(id)');
    assert.ok(sql.includes('idx_businesses_owner'), 'Must index owner_user_id');
    assert.ok(sql.includes('idx_businesses_slug'), 'Must index slug');
  });

  await t.test('2. Migration 010 (Create Business Members) establishes role-based tenancy', () => {
    const migrationPath = resolveDbFile('migrations/010_create_business_members.sql');
    const sql = fs.readFileSync(migrationPath, 'utf8');

    assert.ok(sql.includes('CREATE TABLE IF NOT EXISTS business_members'), 'Must create business_members table');
    assert.ok(sql.includes('business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE'), 'Must cascade on business delete');
    assert.ok(sql.includes('user_id     VARCHAR(64) NOT NULL REFERENCES users(id) ON DELETE CASCADE'), 'Must reference users(id)');
    assert.ok(sql.includes("CHECK (role IN ('owner', 'admin', 'staff'))"), 'Must restrict roles to owner, admin, staff');
    assert.ok(sql.includes('UNIQUE (business_id, user_id)'), 'Must enforce unique user per business');
    assert.ok(sql.includes('idx_members_business'), 'Must index business_id');
    assert.ok(sql.includes('idx_members_user'), 'Must index user_id');
  });

  await t.test('3. Migration 011 (Add Business ID Columns) safely adds nullable FKs to all 8 tenant tables', () => {
    const migrationPath = resolveDbFile('migrations/011_add_business_id_columns.sql');
    const sql = fs.readFileSync(migrationPath, 'utf8');

    const expectedTables = [
      'customers',
      'customer_consent',
      'consent_audit_log',
      'campaigns',
      'campaign_messages',
      'whatsapp_templates',
      'webhook_events',
      'recipient_reservations',
    ];

    for (const table of expectedTables) {
      assert.ok(
        sql.includes(`ALTER TABLE ${table}`),
        `Must alter table ${table}`
      );
      assert.ok(
        sql.includes(`idx_${table}_business_id`),
        `Must create index on ${table}(business_id)`
      );
    }

    // Critical Phase 1 constraint: Columns must be nullable, NOT NULL is strictly forbidden in Phase 1
    assert.ok(!/business_id\s+UUID[^;]*NOT\s+NULL/i.test(sql), 'business_id columns must remain nullable in Phase 1');
  });

  await t.test('4. Migration 012 (Backfill) guarantees idempotency, stable ID, and ambiguity protection', () => {
    const migrationPath = resolveDbFile('migrations/012_backfill_business_ids.sql');
    const sql = fs.readFileSync(migrationPath, 'utf8');

    // 1. Stable initial business ID
    assert.ok(
      sql.includes('a0000000-0000-4000-8000-000000000001'),
      'Must use deterministic initial business UUID'
    );

    // 2. Ambiguity check: fails safe when multiple verified users exist without explicit setting
    assert.ok(
      sql.includes('Ambiguous business owner'),
      'Must fail closed with explanatory error on ambiguous ownership'
    );
    assert.ok(
      sql.includes('glowblast.initial_owner_email'),
      'Must support explicit owner email override via session setting'
    );

    // 3. Idempotent backfill queries
    assert.ok(sql.includes('UPDATE customers SET business_id = v_biz_id WHERE business_id IS NULL;'));
    assert.ok(sql.includes('UPDATE customer_consent SET business_id = v_biz_id WHERE business_id IS NULL;'));
    assert.ok(sql.includes('UPDATE campaigns SET business_id = v_biz_id WHERE business_id IS NULL;'));
    assert.ok(sql.includes('UPDATE campaign_messages SET business_id = v_biz_id WHERE business_id IS NULL;'));
  });

  // --------------------------------------------------------------------------
  // 2. Authentication & Authorization Security Middleware
  // --------------------------------------------------------------------------
  await t.test('5. requireAuth rejects missing and malformed tokens with HTTP 401', async () => {
    // Missing header
    let res = await fetch(`${baseUrl}/api/businesses`);
    assert.strictEqual(res.status, 401);
    let body = await res.json() as any;
    assert.strictEqual(body.error?.code, 'UNAUTHORIZED');

    // Invalid token format
    res = await fetch(`${baseUrl}/api/businesses`, {
      headers: { Authorization: 'Bearer forged.invalid.token' },
    });
    assert.strictEqual(res.status, 401);
    body = await res.json() as any;
    assert.strictEqual(body.error?.code, 'INVALID_TOKEN');
  });

  await t.test('6. requireBusinessMembership rejects arbitrary X-Business-Id without valid membership (Fail-Closed)', async () => {
    // Mock businessStore.getMember to simulate unauthorized user
    const originalGetMember = businessStore.getMember.bind(businessStore);
    businessStore.getMember = async () => null; // No membership found in DB

    try {
      const targetBizId = '00000000-0000-0000-0000-000000000099';
      const res = await fetch(`${baseUrl}/api/businesses/${targetBizId}`, {
        headers: {
          Authorization: `Bearer ${attackerToken}`,
          'x-business-id': targetBizId,
        },
      });

      assert.strictEqual(res.status, 403, 'Must reject arbitrary header with 403');
      const body = await res.json() as any;
      assert.strictEqual(body.error?.code, 'UNAUTHORIZED_BUSINESS_ACCESS');
    } finally {
      businessStore.getMember = originalGetMember;
    }
  });

  await t.test('7. requireBusinessMembership enforces role hierarchy (Staff cannot perform Admin action)', async () => {
    const mockBiz: Business = {
      id: 'a0000000-0000-4000-8000-000000000001',
      slug: 'initial-spa',
      displayName: 'Flagship Spa',
      ownerUserId: testOwnerId,
      timezone: 'Asia/Kolkata',
      isActive: true,
      productionEnabled: true,
      dailyRecipientLimit: 200,
      createdAt: new Date(),
      updatedAt: new Date(),
    };

    const mockStaffMembership: BusinessMember = {
      id: 'mem_1',
      businessId: mockBiz.id,
      userId: testStaffId,
      role: 'staff',
      joinedAt: new Date(),
      updatedAt: new Date(),
    };

    const originalGetMember = businessStore.getMember.bind(businessStore);
    const originalFindById = businessStore.findById.bind(businessStore);

    businessStore.getMember = async (bizId, uId) => {
      if (bizId === mockBiz.id && uId === testStaffId) return mockStaffMembership;
      return null;
    };
    businessStore.findById = async (bizId) => (bizId === mockBiz.id ? mockBiz : null);

    try {
      // Staff attempts PUT update (requires admin)
      const res = await fetch(`${baseUrl}/api/businesses/${mockBiz.id}`, {
        method: 'PUT',
        headers: {
          Authorization: `Bearer ${staffToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ displayName: 'Staff Attempted Change' }),
      });

      assert.strictEqual(res.status, 403);
      const body = await res.json() as any;
      assert.strictEqual(body.error?.code, 'INSUFFICIENT_ROLE_PRIVILEGES');
    } finally {
      businessStore.getMember = originalGetMember;
      businessStore.findById = originalFindById;
    }
  });

  await t.test('8. Authorized owner can access business details and members', async () => {
    const mockBiz: Business = {
      id: 'a0000000-0000-4000-8000-000000000001',
      slug: 'initial-spa',
      displayName: 'Flagship Spa',
      ownerUserId: testOwnerId,
      timezone: 'Asia/Kolkata',
      isActive: true,
      productionEnabled: true,
      dailyRecipientLimit: 200,
      createdAt: new Date(),
      updatedAt: new Date(),
    };

    const mockOwnerMembership: BusinessMember = {
      id: 'mem_owner',
      businessId: mockBiz.id,
      userId: testOwnerId,
      role: 'owner',
      joinedAt: new Date(),
      updatedAt: new Date(),
    };

    const originalGetMember = businessStore.getMember.bind(businessStore);
    const originalFindById = businessStore.findById.bind(businessStore);
    const originalGetMembers = businessStore.getMembers.bind(businessStore);

    businessStore.getMember = async (bizId, uId) => {
      if (bizId === mockBiz.id && uId === testOwnerId) return mockOwnerMembership;
      return null;
    };
    businessStore.findById = async (bizId) => (bizId === mockBiz.id ? mockBiz : null);
    businessStore.getMembers = async () => [mockOwnerMembership];

    try {
      // GET business details
      const resDetails = await fetch(`${baseUrl}/api/businesses/${mockBiz.id}`, {
        headers: { Authorization: `Bearer ${ownerToken}` },
      });
      assert.strictEqual(resDetails.status, 200);
      const detailsBody = await resDetails.json() as any;
      assert.strictEqual(detailsBody.business?.slug, 'initial-spa');
      assert.strictEqual(detailsBody.membership?.role, 'owner');

      // GET members
      const resMembers = await fetch(`${baseUrl}/api/businesses/${mockBiz.id}/members`, {
        headers: { Authorization: `Bearer ${ownerToken}` },
      });
      assert.strictEqual(resMembers.status, 200);
      const membersBody = await resMembers.json() as any;
      assert.strictEqual(membersBody.count, 1);
    } finally {
      businessStore.getMember = originalGetMember;
      businessStore.findById = originalFindById;
      businessStore.getMembers = originalGetMembers;
    }
  });

  await t.test('9. Public routes remain accessible without user authentication', async () => {
    // Health probe
    const healthRes = await fetch(`${baseUrl}/health`);
    assert.strictEqual(healthRes.status, 200);

    // API Health
    const apiHealthRes = await fetch(`${baseUrl}/api/health`);
    assert.strictEqual(apiHealthRes.status, 200);

    // Meta Webhook Verification challenge
    const webhookRes = await fetch(
      `${baseUrl}/api/webhook/whatsapp?hub.mode=subscribe&hub.verify_token=${env.META_VERIFY_TOKEN}&hub.challenge=challenge_token_phase1`
    );
    assert.strictEqual(webhookRes.status, 200);
    const challenge = await webhookRes.text();
    assert.strictEqual(challenge, 'challenge_token_phase1');
  });

  await t.test('10. Pre-migration & post-backfill validation script exists and is query-ready', () => {
    const valPath = resolveDbFile('validation_queries.sql');
    assert.ok(fs.existsSync(valPath), 'Validation queries SQL file must exist');

    const sql = fs.readFileSync(valPath, 'utf8');
    assert.ok(sql.includes('PRE-MIGRATION AUDIT'), 'Must contain pre-migration audit section');
    assert.ok(sql.includes('POST-BACKFILL INTEGRITY VALIDATION'), 'Must contain post-backfill validation section');
    assert.ok(sql.includes('broken_consent_customer_links'), 'Must check customer-consent relational integrity');
    assert.ok(sql.includes('broken_campaign_message_links'), 'Must check campaign-message relational integrity');
    assert.ok(sql.includes('unassigned_customers'), 'Must verify zero unassigned records');
  });
});
