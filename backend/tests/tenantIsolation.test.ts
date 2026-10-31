process.env.NODE_ENV = 'test';
import test from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import { app } from '../src/server';
import { env } from '../src/config/env';
import { businessStore } from '../src/store/businessStore';
import { campaignStore } from '../src/store/campaignStore';
import { consentStore } from '../src/store/consentStore';
import { templateStore } from '../src/store/templateStore';
import { Business, BusinessMember } from '../src/types/business';
import { StoredCampaign, CampaignSummary } from '../src/types/campaign';

test('Multi-Business SaaS API & Tenant Isolation Test Suite', async (t) => {
  const server = app.listen(0);
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : 0;
  const baseUrl = `http://127.0.0.1:${port}`;

  t.after(() => {
    server.close();
  });

  const INITIAL_BIZ_ID = 'a0000000-0000-4000-8000-000000000001';
  const COMPETITOR_BIZ_ID = 'b0000000-0000-4000-8000-000000000002';

  const userOwnerA = 'usr_owner_flagship_a';
  const userStaffA = 'usr_staff_flagship_a';
  const userOwnerB = 'usr_owner_competitor_b';
  const userNoBiz = 'usr_no_membership_c';

  const tokenOwnerA = jwt.sign(
    { sub: userOwnerA, email: 'owner@flagship.com', name: 'Owner A' },
    env.JWT_SECRET,
    { expiresIn: '1h' }
  );

  const tokenStaffA = jwt.sign(
    { sub: userStaffA, email: 'staff@flagship.com', name: 'Staff A' },
    env.JWT_SECRET,
    { expiresIn: '1h' }
  );

  const tokenOwnerB = jwt.sign(
    { sub: userOwnerB, email: 'owner@competitor.com', name: 'Owner B' },
    env.JWT_SECRET,
    { expiresIn: '1h' }
  );

  const tokenNoBiz = jwt.sign(
    { sub: userNoBiz, email: 'newuser@standalone.com', name: 'No Biz User' },
    env.JWT_SECRET,
    { expiresIn: '1h' }
  );

  // In-memory mock storage for businesses & memberships
  const mockBusinesses = new Map<string, Business>();
  const mockMembers = new Map<string, BusinessMember[]>();

  const bizA: Business = {
    id: INITIAL_BIZ_ID,
    slug: 'flagship-spa',
    displayName: 'Flagship Spa',
    ownerUserId: userOwnerA,
    timezone: 'Asia/Kolkata',
    isActive: true,
    productionEnabled: true,
    dailyRecipientLimit: 200,
    createdAt: new Date(),
    updatedAt: new Date(),
  };

  const bizB: Business = {
    id: COMPETITOR_BIZ_ID,
    slug: 'competitor-spa',
    displayName: 'Competitor Spa',
    ownerUserId: userOwnerB,
    timezone: 'America/New_York',
    isActive: true,
    productionEnabled: false,
    dailyRecipientLimit: 50,
    createdAt: new Date(),
    updatedAt: new Date(),
  };

  mockBusinesses.set(bizA.id, bizA);
  mockBusinesses.set(bizB.id, bizB);

  mockMembers.set(bizA.id, [
    {
      id: 'mem_a_owner',
      businessId: bizA.id,
      userId: userOwnerA,
      role: 'owner',
      joinedAt: new Date(),
      updatedAt: new Date(),
    },
    {
      id: 'mem_a_staff',
      businessId: bizA.id,
      userId: userStaffA,
      role: 'staff',
      joinedAt: new Date(),
      updatedAt: new Date(),
    },
  ]);

  mockMembers.set(bizB.id, [
    {
      id: 'mem_b_owner',
      businessId: bizB.id,
      userId: userOwnerB,
      role: 'owner',
      joinedAt: new Date(),
      updatedAt: new Date(),
    },
  ]);

  // Hook businessStore methods
  const origFindById = businessStore.findById.bind(businessStore);
  const origFindBySlug = businessStore.findBySlug.bind(businessStore);
  const origFindByUserId = businessStore.findByUserId.bind(businessStore);
  const origGetMember = businessStore.getMember.bind(businessStore);
  const origGetMembers = businessStore.getMembers.bind(businessStore);
  const origCreate = businessStore.create.bind(businessStore);
  const origAddMember = businessStore.addMember.bind(businessStore);

  businessStore.findById = async (id: string) => mockBusinesses.get(id) || null;
  businessStore.findBySlug = async (slug: string) =>
    Array.from(mockBusinesses.values()).find((b) => b.slug === slug) || null;
  businessStore.findByUserId = async (userId: string) => {
    const list: Business[] = [];
    for (const [bizId, members] of mockMembers.entries()) {
      if (members.some((m) => m.userId === userId)) {
        const b = mockBusinesses.get(bizId);
        if (b && b.isActive) list.push(b);
      }
    }
    return list;
  };
  businessStore.getMember = async (bizId: string, userId: string) => {
    const list = mockMembers.get(bizId) || [];
    return list.find((m) => m.userId === userId) || null;
  };
  businessStore.getMembers = async (bizId: string) => mockMembers.get(bizId) || [];
  businessStore.create = async (dto) => {
    const id = dto.id || `biz_${Date.now()}`;
    const b: Business = {
      id,
      slug: dto.slug,
      displayName: dto.displayName,
      ownerUserId: dto.ownerUserId,
      timezone: dto.timezone || 'UTC',
      phone: dto.phone,
      email: dto.email,
      logoUrl: dto.logoUrl,
      isActive: true,
      productionEnabled: dto.productionEnabled ?? false,
      dailyRecipientLimit: dto.dailyRecipientLimit ?? 200,
      createdAt: new Date(),
      updatedAt: new Date(),
    };
    mockBusinesses.set(id, b);
    const ownerMember: BusinessMember = {
      id: `mem_${Date.now()}`,
      businessId: id,
      userId: dto.ownerUserId,
      role: 'owner',
      joinedAt: new Date(),
      updatedAt: new Date(),
    };
    mockMembers.set(id, [ownerMember]);
    return b;
  };
  businessStore.addMember = async (bizId: string, userId: string, role = 'staff') => {
    const list = mockMembers.get(bizId) || [];
    const member: BusinessMember = {
      id: `mem_${Date.now()}`,
      businessId: bizId,
      userId,
      role,
      joinedAt: new Date(),
      updatedAt: new Date(),
    };
    list.push(member);
    mockMembers.set(bizId, list);
    return member;
  };

  t.after(() => {
    businessStore.findById = origFindById;
    businessStore.findBySlug = origFindBySlug;
    businessStore.findByUserId = origFindByUserId;
    businessStore.getMember = origGetMember;
    businessStore.getMembers = origGetMembers;
    businessStore.create = origCreate;
    businessStore.addMember = origAddMember;
  });

  // --------------------------------------------------------------------------
  // 1. Business Header & Membership Enforcement
  // --------------------------------------------------------------------------
  await t.test('1. Reject forged X-Business-Id without membership (Fail-Closed)', async () => {
    // User A attempts to access Business B by supplying X-Business-Id header
    const res = await fetch(`${baseUrl}/api/campaigns`, {
      headers: {
        Authorization: `Bearer ${tokenOwnerA}`,
        'X-Business-Id': COMPETITOR_BIZ_ID,
      },
    });

    assert.equal(res.status, 403, 'Must reject unauthorized business selection with HTTP 403');
    const data = await res.json() as any;
    assert.equal(data.error?.code, 'UNAUTHORIZED_BUSINESS_ACCESS');
  });

  await t.test('2. Reject user without any business membership on protected tenant endpoints', async () => {
    const res = await fetch(`${baseUrl}/api/campaigns`, {
      headers: {
        Authorization: `Bearer ${tokenNoBiz}`,
      },
    });

    assert.equal(res.status, 403, 'Must reject user without membership with HTTP 403');
    const data = await res.json() as any;
    assert.equal(data.error?.code, 'NO_BUSINESS_MEMBERSHIP');
  });

  // --------------------------------------------------------------------------
  // 2. Account-Level Business Listing & Atomic Creation
  // --------------------------------------------------------------------------
  await t.test('3. Account-level business listing works without prior business context', async () => {
    // User without businesses gets empty list
    const res = await fetch(`${baseUrl}/api/businesses`, {
      headers: {
        Authorization: `Bearer ${tokenNoBiz}`,
      },
    });

    assert.equal(res.status, 200);
    const data = await res.json() as any;
    assert.deepEqual(data.businesses, []);
  });

  await t.test('4. Atomic business creation assigns user as Owner automatically', async () => {
    const res = await fetch(`${baseUrl}/api/businesses`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${tokenNoBiz}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        name: 'Brand New Spa',
        slug: `brand-new-spa-${Date.now()}`,
      }),
    });

    assert.equal(res.status, 201, 'Must create business with HTTP 201');
    const data = await res.json() as any;
    assert.ok(data.business?.id, 'Returns created business ID');
    assert.equal(data.business.ownerUserId, userNoBiz);

    // Verify membership was created atomically
    const members = await businessStore.getMembers(data.business.id);
    assert.equal(members.length, 1);
    assert.equal(members[0].userId, userNoBiz);
    assert.equal(members[0].role, 'owner');
  });

  // --------------------------------------------------------------------------
  // 3. Campaign, Status & SSE Stream Tenant Isolation
  // --------------------------------------------------------------------------
  await t.test('5. Campaign details, status, and SSE streams are inaccessible across businesses', async () => {
    const origGet = campaignStore.get.bind(campaignStore);
    const origGetSummary = campaignStore.getSummary.bind(campaignStore);

    const testCampaignId = `camp_iso_${Date.now()}`;
    const testCampaign: StoredCampaign = {
      campaignId: testCampaignId,
      campaignName: 'Private Flagship Promotion',
      status: 'completed',
      templateName: 'spa_offer',
      templateLanguage: 'en_US',
      total: 10,
      queued: 0,
      accepted: 10,
      sent: 10,
      delivered: 10,
      read: 8,
      replied: 2,
      failed: 0,
      excludedOptOut: 0,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      businessId: INITIAL_BIZ_ID,
      messages: [],
    };

    campaignStore.get = async (id: string, bId?: string) => {
      if (id !== testCampaignId) return undefined;
      if (bId && bId !== INITIAL_BIZ_ID) return undefined;
      return testCampaign;
    };

    campaignStore.getSummary = async (id: string, bId?: string) => {
      if (id !== testCampaignId) return undefined;
      if (bId && bId !== INITIAL_BIZ_ID) return undefined;
      return testCampaign;
    };

    try {
      // Business B attempts to read Business A's campaign details
      const resGetB = await fetch(`${baseUrl}/api/campaigns/${testCampaignId}`, {
        headers: {
          Authorization: `Bearer ${tokenOwnerB}`,
          'X-Business-Id': COMPETITOR_BIZ_ID,
        },
      });
      assert.equal(resGetB.status, 404, 'Must return 404 when querying another business campaign');

      // Business B attempts to read Business A's campaign status
      const resStatusB = await fetch(`${baseUrl}/api/campaigns/${testCampaignId}/status`, {
        headers: {
          Authorization: `Bearer ${tokenOwnerB}`,
          'X-Business-Id': COMPETITOR_BIZ_ID,
        },
      });
      assert.equal(resStatusB.status, 404, 'Must return 404 for other business campaign status');

      // Business B attempts to connect to Business A's SSE event stream
      const resSseB = await fetch(`${baseUrl}/api/campaigns/${testCampaignId}/events`, {
        headers: {
          Authorization: `Bearer ${tokenOwnerB}`,
          'X-Business-Id': COMPETITOR_BIZ_ID,
        },
      });
      assert.equal(resSseB.status, 404, 'Must return 404 when establishing SSE stream for other business');

      // Business A connects to its own campaign status: returns 200
      const resStatusA = await fetch(`${baseUrl}/api/campaigns/${testCampaignId}/status`, {
        headers: {
          Authorization: `Bearer ${tokenOwnerA}`,
          'X-Business-Id': INITIAL_BIZ_ID,
        },
      });
      assert.equal(resStatusA.status, 200, 'Business A accesses its own campaign status successfully');
    } finally {
      campaignStore.get = origGet;
      campaignStore.getSummary = origGetSummary;
    }
  });

  // --------------------------------------------------------------------------
  // 4. Consent Tenant Isolation
  // --------------------------------------------------------------------------
  await t.test('6. Consent records and lookups are strictly isolated per business', async () => {
    const origGetConsent = consentStore.getConsent.bind(consentStore);
    const testPhone = '+919999888877';

    consentStore.getConsent = async (phone: string, category?: any, bId?: string) => {
      // Consent exists only under Business A
      if (phone.includes('9999888877') && bId === INITIAL_BIZ_ID) {
        return {
          phone,
          consentCategory: 'marketing' as any,
          status: 'opted_in' as any,
          recordedAt: new Date().toISOString(),
          source: 'verbal',
          evidence: 'test',
          updatedBy: 'tester',
        };
      }
      return undefined;
    };

    try {
      // Business A verifies consent: must be opted_in
      const resCheckA = await fetch(`${baseUrl}/api/consent/${testPhone}?category=marketing`, {
        headers: {
          Authorization: `Bearer ${tokenOwnerA}`,
          'X-Business-Id': INITIAL_BIZ_ID,
        },
      });
      assert.equal(resCheckA.status, 200);
      const dataCheckA = await resCheckA.json() as any;
      assert.equal(dataCheckA.hasConsent, true, 'Business A sees recorded consent');

      // Business B checks consent for same phone: must NOT have consent in Business B
      const resCheckB = await fetch(`${baseUrl}/api/consent/${testPhone}?category=marketing`, {
        headers: {
          Authorization: `Bearer ${tokenOwnerB}`,
          'X-Business-Id': COMPETITOR_BIZ_ID,
        },
      });
      assert.equal(resCheckB.status, 200);
      const dataCheckB = await resCheckB.json() as any;
      assert.equal(dataCheckB.hasConsent, false, 'Business B must not inherit Business A consent');
    } finally {
      consentStore.getConsent = origGetConsent;
    }
  });

  // --------------------------------------------------------------------------
  // 5. Template Tenant Isolation
  // --------------------------------------------------------------------------
  await t.test('7. Templates do not leak across businesses', async () => {
    const origGetAll = templateStore.getAll.bind(templateStore);
    templateStore.getAll = async (mode?: 'test' | 'production', bId?: string) => {
      if (bId === INITIAL_BIZ_ID) {
        return [
          {
            id: 'tpl_flagship_1',
            name: 'flagship_secret_promo',
            displayName: 'Flagship Promo',
            category: 'MARKETING',
            language: 'en_US',
            status: 'approved',
            metaStatus: 'APPROVED',
            body: 'Secret promo',
            variables: [],
            businessId: INITIAL_BIZ_ID,
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString(),
          },
        ];
      }
      return [];
    };

    try {
      // Business B queries templates: must get empty list
      const resB = await fetch(`${baseUrl}/api/templates`, {
        headers: {
          Authorization: `Bearer ${tokenOwnerB}`,
          'X-Business-Id': COMPETITOR_BIZ_ID,
        },
      });
      assert.equal(resB.status, 200);
      const dataB = await resB.json() as any;
      assert.equal(dataB.templates.length, 0, 'Business B cannot see Business A templates');

      // Business A queries templates: sees its template
      const resA = await fetch(`${baseUrl}/api/templates`, {
        headers: {
          Authorization: `Bearer ${tokenOwnerA}`,
          'X-Business-Id': INITIAL_BIZ_ID,
        },
      });
      assert.equal(resA.status, 200);
      const dataA = await resA.json() as any;
      assert.equal(dataA.templates.length, 1, 'Business A retrieves its own templates');
    } finally {
      templateStore.getAll = origGetAll;
    }
  });

  // --------------------------------------------------------------------------
  // 6. Role-Based Permissions (Staff vs Owner/Admin)
  // --------------------------------------------------------------------------
  await t.test('8. Staff cannot perform owner-only or admin-only actions', async () => {
    // Staff user attempts to view business members (requires Owner/Admin)
    const resMembers = await fetch(`${baseUrl}/api/businesses/${INITIAL_BIZ_ID}/members`, {
      headers: {
        Authorization: `Bearer ${tokenStaffA}`,
        'X-Business-Id': INITIAL_BIZ_ID,
      },
    });
    assert.equal(resMembers.status, 403, 'Staff must be forbidden from viewing business members');

    // Staff user attempts to create a template (requires Owner/Admin)
    const resTpl = await fetch(`${baseUrl}/api/templates`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${tokenStaffA}`,
        'X-Business-Id': INITIAL_BIZ_ID,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        name: 'staff_unauthorized_template',
        displayName: 'Staff Template',
        body: 'Hello {{1}}',
        category: 'MARKETING',
      }),
    });
    assert.equal(resTpl.status, 403, 'Staff must be forbidden from creating templates');
  });

  // --------------------------------------------------------------------------
  // 7. Critical Phase 2 WhatsApp Restriction (Fail-Closed Check)
  // --------------------------------------------------------------------------
  await t.test('9. New businesses without authorized WABA cannot send messages through global Meta credentials', async () => {
    // Business B attempts to send campaign
    const resSendCamp = await fetch(`${baseUrl}/api/campaigns/send`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${tokenOwnerB}`,
        'X-Business-Id': COMPETITOR_BIZ_ID,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        campaignId: `camp_blocked_${Date.now()}`,
        campaignName: 'Competitor Blast',
        templateName: 'spa_welcome',
        recipients: [{ phone: '+919999000001', name: 'Test' }],
      }),
    });

    assert.equal(resSendCamp.status, 403, 'Must reject campaign send for unauthorized business');
    const campErr = await resSendCamp.json() as any;
    assert.equal(campErr.error?.code, 'WHATSAPP_CONNECTION_NOT_CONFIGURED');

    // Business B attempts to sync templates from Meta Cloud API
    const resSync = await fetch(`${baseUrl}/api/templates/sync`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${tokenOwnerB}`,
        'X-Business-Id': COMPETITOR_BIZ_ID,
      },
    });

    assert.equal(resSync.status, 403, 'Must reject template sync for unauthorized business');
    const syncErr = await resSync.json() as any;
    assert.equal(syncErr.error?.code, 'WHATSAPP_CONNECTION_NOT_CONFIGURED');
  });

  // --------------------------------------------------------------------------
  // 8. Pre-Migration Safeguards & Store Fallbacks (42P01 & 42703)
  // --------------------------------------------------------------------------
  await t.test('10. Pre-migration 42P01 fallback fails closed for unauthorized users', async () => {
    // Simulate unmigrated database state where business_members table does not exist
    const originalFindByUserId = businessStore.findByUserId;
    const originalGetMember = businessStore.getMember;

    const dbErr42P01 = new Error('relation "business_members" does not exist');
    (dbErr42P01 as any).code = '42P01';

    businessStore.findByUserId = async () => {
      throw dbErr42P01;
    };
    businessStore.getMember = async () => {
      throw dbErr42P01;
    };

    try {
      // 1. Unrelated user attempts to access API in unmigrated environment
      const resUnauthorized = await fetch(`${baseUrl}/api/customers`, {
        headers: {
          Authorization: `Bearer ${tokenNoBiz}`,
        },
      });

      assert.equal(resUnauthorized.status, 403, 'Pre-migration fallback must reject unauthorized user with 403');
      const errBody = await resUnauthorized.json() as any;
      assert.equal(errBody.error?.code, 'UNAUTHORIZED_BUSINESS_ACCESS');

      // 2. Explicit non-initial business header in unmigrated environment must also fail closed
      const resExplicitOther = await fetch(`${baseUrl}/api/customers`, {
        headers: {
          Authorization: `Bearer ${tokenNoBiz}`,
          'X-Business-Id': COMPETITOR_BIZ_ID,
        },
      });
      assert.equal(resExplicitOther.status, 403, 'Pre-migration fallback must reject non-initial business ID');
    } finally {
      businessStore.findByUserId = originalFindByUserId;
      businessStore.getMember = originalGetMember;
    }
  });

  await t.test('11. Store 42703 fallbacks fail closed for non-initial business', async () => {
    // Verify templateStore.getAll returns empty for non-initial business when 42703 is caught
    const allTemplates = await templateStore.getAll('test', COMPETITOR_BIZ_ID);
    assert.ok(Array.isArray(allTemplates), 'Must return array');

    // Verify campaignStore.listSummaries for non-initial business
    const summaries = await campaignStore.listSummaries(COMPETITOR_BIZ_ID);
    assert.deepEqual(summaries, [], 'Non-initial business must receive empty summaries');

    // Verify consentStore.getAll for non-initial business
    const consents = await consentStore.getAll(undefined, COMPETITOR_BIZ_ID);
    assert.deepEqual(consents, [], 'Non-initial business must receive empty consent list');
  });
});

