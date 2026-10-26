process.env.NODE_ENV = 'test';
process.env.WABA_TOKEN_ENCRYPTION_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'http';
import jwt from 'jsonwebtoken';
import app from '../src/server';
import { env } from '../src/config/env';
import { businessStore } from '../src/store/businessStore';
import { userStore } from '../src/store/userStore';
import { Business, BusinessMember, BusinessInvitation } from '../src/types/business';

function createAuthToken(user: { id: string; email: string; name: string }): string {
  return jwt.sign(
    { sub: user.id, id: user.id, email: user.email, name: user.name },
    env.JWT_SECRET,
    { expiresIn: '1h' }
  );
}

test('Phase 4: Team Management, Roles & Business Profile Test Suite', async (t) => {
  let server: http.Server;
  let baseUrl: string;

  const bizA: Business = {
    id: '22222222-2222-4000-8000-222222222222',
    slug: 'lotus-wellness',
    displayName: 'Lotus Wellness Spa',
    ownerUserId: 'usr_owner_a',
    timezone: 'Asia/Kolkata',
    isActive: true,
    productionEnabled: true,
    dailyRecipientLimit: 200,
    createdAt: new Date(),
    updatedAt: new Date(),
  };

  const bizB: Business = {
    id: '33333333-3333-4000-8000-333333333333',
    slug: 'ocean-spa',
    displayName: 'Ocean Breeze Spa',
    ownerUserId: 'usr_owner_b',
    timezone: 'Asia/Kolkata',
    isActive: true,
    productionEnabled: true,
    dailyRecipientLimit: 200,
    createdAt: new Date(),
    updatedAt: new Date(),
  };

  const ownerA = { id: 'usr_owner_a', email: 'owner.a@lotus.com', name: 'Aarav Owner' };
  const adminA = { id: 'usr_admin_a', email: 'admin.a@lotus.com', name: 'Aditi Admin' };
  const staffA = { id: 'usr_staff_a', email: 'staff.a@lotus.com', name: 'Siddharth Staff' };
  const outsideUser = { id: 'usr_outside', email: 'outside@gmail.com', name: 'Outside User' };
  const unverifiedUser = { id: 'usr_unverified', email: 'invitee@lotus.com', name: 'Invited Candidate' };
  const verifiedInvitee = { id: 'usr_verified_invitee', email: 'newmember@lotus.com', name: 'New Team Member' };

  const tokenOwnerA = createAuthToken(ownerA);
  const tokenAdminA = createAuthToken(adminA);
  const tokenStaffA = createAuthToken(staffA);
  const tokenOutside = createAuthToken(outsideUser);
  const tokenUnverified = createAuthToken(unverifiedUser);
  const tokenVerifiedInvitee = createAuthToken(verifiedInvitee);

  t.before(async () => {
    // Reset mocks
    businessStore.clearMock();

    // Setup mock businesses
    await businessStore.create({
      id: bizA.id,
      slug: bizA.slug,
      displayName: bizA.displayName,
      ownerUserId: ownerA.id,
    });
    await businessStore.create({
      id: bizB.id,
      slug: bizB.slug,
      displayName: bizB.displayName,
      ownerUserId: 'usr_owner_b',
    });

    // Setup mock members
    businessStore.setMockMember({
      id: 'bm_owner_a',
      businessId: bizA.id,
      userId: ownerA.id,
      role: 'owner',
      joinedAt: new Date(),
      updatedAt: new Date(),
      name: ownerA.name,
      email: ownerA.email,
    });
    businessStore.setMockMember({
      id: 'bm_admin_a',
      businessId: bizA.id,
      userId: adminA.id,
      role: 'admin',
      joinedAt: new Date(),
      updatedAt: new Date(),
      name: adminA.name,
      email: adminA.email,
    });
    businessStore.setMockMember({
      id: 'bm_staff_a',
      businessId: bizA.id,
      userId: staffA.id,
      role: 'staff',
      joinedAt: new Date(),
      updatedAt: new Date(),
      name: staffA.name,
      email: staffA.email,
    });

    // Setup mock users in userStore
    const nowStr = new Date().toISOString();
    userStore.setMockUser({
      id: ownerA.id,
      name: ownerA.name,
      email: ownerA.email,
      passwordHash: 'hash',
      emailVerified: true,
      createdAt: nowStr,
      updatedAt: nowStr,
    });
    userStore.setMockUser({
      id: adminA.id,
      name: adminA.name,
      email: adminA.email,
      passwordHash: 'hash',
      emailVerified: true,
      createdAt: nowStr,
      updatedAt: nowStr,
    });
    userStore.setMockUser({
      id: staffA.id,
      name: staffA.name,
      email: staffA.email,
      passwordHash: 'hash',
      emailVerified: true,
      createdAt: nowStr,
      updatedAt: nowStr,
    });
    userStore.setMockUser({
      id: outsideUser.id,
      name: outsideUser.name,
      email: outsideUser.email,
      passwordHash: 'hash',
      emailVerified: true,
      createdAt: nowStr,
      updatedAt: nowStr,
    });
    userStore.setMockUser({
      id: unverifiedUser.id,
      name: unverifiedUser.name,
      email: unverifiedUser.email,
      passwordHash: 'hash',
      emailVerified: false, // NOT verified
      createdAt: nowStr,
      updatedAt: nowStr,
    });
    userStore.setMockUser({
      id: verifiedInvitee.id,
      name: verifiedInvitee.name,
      email: verifiedInvitee.email,
      passwordHash: 'hash',
      emailVerified: true, // Verified
      createdAt: nowStr,
      updatedAt: nowStr,
    });

    // Start server on ephemeral port
    await new Promise<void>((resolve) => {
      server = app.listen(0, () => {
        const addr = server.address() as any;
        baseUrl = `http://localhost:${addr.port}`;
        resolve();
      });
    });
  });

  t.after(async () => {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  });

  await t.test('1. Member listing returns roster with role badges and user info', async () => {
    const res = await fetch(`${baseUrl}/api/businesses/${bizA.id}/members`, {
      headers: {
        Authorization: `Bearer ${tokenAdminA}`,
        'X-Business-Id': bizA.id,
      },
    });

    assert.strictEqual(res.status, 200);
    const data = (await res.json()) as any;
    assert.strictEqual(data.success, true);
    assert.ok(data.members.length >= 3);
    const roles = data.members.map((m: any) => m.role);
    assert.ok(roles.includes('owner'));
    assert.ok(roles.includes('admin'));
    assert.ok(roles.includes('staff'));
  });

  await t.test('2. Admin can invite a new team member with secure expiry token', async () => {
    const res = await fetch(`${baseUrl}/api/businesses/${bizA.id}/invitations`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${tokenAdminA}`,
        'X-Business-Id': bizA.id,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        email: 'newmember@lotus.com',
        role: 'staff',
      }),
    });

    assert.strictEqual(res.status, 201);
    const data = (await res.json()) as any;
    assert.strictEqual(data.success, true);
    assert.strictEqual(data.invitation.email, 'newmember@lotus.com');
    assert.strictEqual(data.invitation.role, 'staff');
    assert.ok(data.invitation.token.length >= 32);
    assert.ok(new Date(data.invitation.expiresAt) > new Date());
  });

  await t.test('3. Inviting an existing active member returns 409 conflict', async () => {
    const res = await fetch(`${baseUrl}/api/businesses/${bizA.id}/invitations`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${tokenAdminA}`,
        'X-Business-Id': bizA.id,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        email: staffA.email,
        role: 'admin',
      }),
    });

    assert.strictEqual(res.status, 409);
    const data = (await res.json()) as any;
    assert.strictEqual(data.error.code, 'ALREADY_A_MEMBER');
  });

  await t.test('4. Staff cannot invite new members (enforces admin/owner role)', async () => {
    const res = await fetch(`${baseUrl}/api/businesses/${bizA.id}/invitations`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${tokenStaffA}`,
        'X-Business-Id': bizA.id,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        email: 'random@test.com',
        role: 'staff',
      }),
    });

    assert.strictEqual(res.status, 403);
    const data = (await res.json()) as any;
    assert.strictEqual(data.error.code, 'INSUFFICIENT_ROLE_PRIVILEGES');
  });

  await t.test('5. Accepting an invitation with unverified email fails closed (403 EMAIL_NOT_VERIFIED)', async () => {
    // Create invitation for unverified user
    const inv = await businessStore.createInvitation({
      businessId: bizA.id,
      email: unverifiedUser.email,
      role: 'staff',
      token: 'unverified_user_token_123456789012345',
      invitedBy: adminA.id,
      expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
    });

    const res = await fetch(`${baseUrl}/api/businesses/invitations/accept`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${tokenUnverified}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        token: inv.token,
      }),
    });

    assert.strictEqual(res.status, 403);
    const data = (await res.json()) as any;
    assert.strictEqual(data.error.code, 'EMAIL_NOT_VERIFIED');
  });

  await t.test('6. Accepting an invitation with a mismatched email session fails closed (403 EMAIL_MISMATCH)', async () => {
    // Token was sent to newmember@lotus.com, but outsideUser tries to accept it
    const pendingInvs = await businessStore.getPendingInvitations(bizA.id);
    const targetInv = pendingInvs.find((i) => i.email === 'newmember@lotus.com');
    assert.ok(targetInv, 'Target invitation should exist');

    const res = await fetch(`${baseUrl}/api/businesses/invitations/accept`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${tokenOutside}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        token: targetInv.token,
      }),
    });

    assert.strictEqual(res.status, 403);
    const data = (await res.json()) as any;
    assert.strictEqual(data.error.code, 'EMAIL_MISMATCH');
  });

  await t.test('7. Accepting an expired invitation fails closed (400 INVITATION_EXPIRED)', async () => {
    const expiredInv = await businessStore.createInvitation({
      businessId: bizA.id,
      email: verifiedInvitee.email,
      role: 'staff',
      token: 'expired_token_test_1234567890123456',
      invitedBy: adminA.id,
      expiresAt: new Date(Date.now() - 3600000), // Expired 1 hour ago
    });

    const res = await fetch(`${baseUrl}/api/businesses/invitations/accept`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${tokenVerifiedInvitee}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        token: expiredInv.token,
      }),
    });

    assert.strictEqual(res.status, 400);
    const data = (await res.json()) as any;
    assert.strictEqual(data.error.code, 'INVITATION_EXPIRED');
  });

  await t.test('8. Accepting valid invitation with verified matching email succeeds', async () => {
    const validInv = await businessStore.createInvitation({
      businessId: bizA.id,
      email: verifiedInvitee.email,
      role: 'staff',
      token: 'valid_token_test_12345678901234567',
      invitedBy: adminA.id,
      expiresAt: new Date(Date.now() + 86400000),
    });

    const res = await fetch(`${baseUrl}/api/businesses/invitations/accept`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${tokenVerifiedInvitee}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        token: validInv.token,
      }),
    });

    assert.strictEqual(res.status, 200);
    const data = (await res.json()) as any;
    assert.strictEqual(data.success, true);
    assert.strictEqual(data.businessId, bizA.id);
    assert.strictEqual(data.role, 'staff');

    // Confirm user is now a member in businessStore
    const newMember = await businessStore.getMember(bizA.id, verifiedInvitee.id);
    assert.ok(newMember);
    assert.strictEqual(newMember.role, 'staff');
  });

  await t.test('9. Last owner protection: Demoting the only owner is strictly rejected (400 CANNOT_DEMOTE_LAST_OWNER)', async () => {
    const res = await fetch(`${baseUrl}/api/businesses/${bizA.id}/members/${ownerA.id}`, {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${tokenOwnerA}`,
        'X-Business-Id': bizA.id,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        role: 'admin',
      }),
    });

    assert.strictEqual(res.status, 400);
    const data = (await res.json()) as any;
    assert.strictEqual(data.error.code, 'CANNOT_DEMOTE_LAST_OWNER');
  });

  await t.test('10. Last owner protection: Removing the only owner is strictly rejected (400 CANNOT_REMOVE_LAST_OWNER)', async () => {
    const res = await fetch(`${baseUrl}/api/businesses/${bizA.id}/members/${ownerA.id}`, {
      method: 'DELETE',
      headers: {
        Authorization: `Bearer ${tokenOwnerA}`,
        'X-Business-Id': bizA.id,
      },
    });

    assert.strictEqual(res.status, 400);
    const data = (await res.json()) as any;
    assert.strictEqual(data.error.code, 'CANNOT_REMOVE_LAST_OWNER');
  });

  await t.test('11. Cross-business member management is strictly denied (403 FORBIDDEN)', async () => {
    // Admin of Biz A tries to manage members of Biz B
    const res = await fetch(`${baseUrl}/api/businesses/${bizB.id}/members`, {
      headers: {
        Authorization: `Bearer ${tokenAdminA}`,
        'X-Business-Id': bizB.id,
      },
    });

    assert.strictEqual(res.status, 403);
    const data = (await res.json()) as any;
    assert.strictEqual(data.error.code, 'UNAUTHORIZED_BUSINESS_ACCESS');
  });

  await t.test('12. Business profile update: Admin/Owner can update profile details', async () => {
    const res = await fetch(`${baseUrl}/api/businesses/${bizA.id}`, {
      method: 'PUT',
      headers: {
        Authorization: `Bearer ${tokenOwnerA}`,
        'X-Business-Id': bizA.id,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        displayName: 'Lotus Luxury Spa & Wellness',
        phone: '+91 9876543210',
        timezone: 'Asia/Kolkata',
      }),
    });

    assert.strictEqual(res.status, 200);
    const data = (await res.json()) as any;
    assert.strictEqual(data.success, true);
    assert.strictEqual(data.business.displayName, 'Lotus Luxury Spa & Wellness');
  });

  await t.test('13. Business profile update: Staff cannot update business profile (403 FORBIDDEN)', async () => {
    const res = await fetch(`${baseUrl}/api/businesses/${bizA.id}`, {
      method: 'PUT',
      headers: {
        Authorization: `Bearer ${tokenStaffA}`,
        'X-Business-Id': bizA.id,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        displayName: 'Staff Tampered Name',
      }),
    });

    assert.strictEqual(res.status, 403);
    const data = (await res.json()) as any;
    assert.strictEqual(data.error.code, 'INSUFFICIENT_ROLE_PRIVILEGES');
  });
});
