import { getPool } from '../db/pool';
import {
  Business,
  BusinessMember,
  BusinessRole,
  BusinessInvitation,
  InvitationStatus,
  CreateBusinessDTO,
  UpdateBusinessDTO,
} from '../types/business';

export class BusinessStore {
  private mockBusinesses = new Map<string, Business>();
  private mockInvitations = new Map<string, BusinessInvitation>();
  private mockMembers = new Map<string, BusinessMember>();

  public clearMock(): void {
    this.mockBusinesses.clear();
    this.mockInvitations.clear();
    this.mockMembers.clear();
  }

  public setMockBusiness(biz: Business): void {
    this.mockBusinesses.set(biz.id, biz);
    this.mockBusinesses.set(biz.slug, biz);
  }

  public setMockMember(member: BusinessMember): void {
    this.mockMembers.set(`${member.businessId}:${member.userId}`, member);
  }

  public setMockInvitation(inv: BusinessInvitation): void {
    this.mockInvitations.set(inv.token, inv);
  }
  public async findById(id: string): Promise<Business | null> {
    const mock = this.mockBusinesses.get(id);
    if (mock) return mock;

    try {
      const pool = getPool();
      const res = await pool.query<{
        id: string;
        slug: string;
        display_name: string;
        owner_user_id: string;
        phone: string | null;
        email: string | null;
        timezone: string;
        logo_url: string | null;
        is_active: boolean;
        production_enabled: boolean;
        daily_recipient_limit: number;
        created_at: Date;
        updated_at: Date;
      }>(
        `SELECT id, slug, display_name, owner_user_id, phone, email, timezone,
                logo_url, is_active, production_enabled, daily_recipient_limit,
                created_at, updated_at
         FROM businesses
         WHERE id = $1
         LIMIT 1;`,
        [id]
      );

      if (res.rows.length === 0) return null;
      return this.mapBusinessRow(res.rows[0]);
    } catch (err: any) {
      if (err.code === '42P01') return this.mockBusinesses.get(id) || null;
      throw err;
    }
  }

  /**
   * Finds a business by its URL-safe slug.
   */
  public async findBySlug(slug: string): Promise<Business | null> {
    const normalizedSlug = slug.trim().toLowerCase();
    const mock = this.mockBusinesses.get(normalizedSlug);
    if (mock) return mock;

    try {
      const pool = getPool();
      const res = await pool.query(
        `SELECT id, slug, display_name, owner_user_id, phone, email, timezone,
                logo_url, is_active, production_enabled, daily_recipient_limit,
                created_at, updated_at
         FROM businesses
         WHERE slug = $1
         LIMIT 1;`,
        [normalizedSlug]
      );

      if (res.rows.length === 0) return null;
      return this.mapBusinessRow(res.rows[0]);
    } catch (err: any) {
      if (err.code === '42P01') return this.mockBusinesses.get(normalizedSlug) || null;
      throw err;
    }
  }

  /**
   * Retrieves all businesses where the specified user is an authorized member.
   */
  public async findByUserId(userId: string): Promise<Business[]> {
    const mockList = Array.from(this.mockMembers.values()).filter((m) => m.userId === userId);
    if (mockList.length > 0) {
      return mockList
        .map((m) => this.mockBusinesses.get(m.businessId))
        .filter((b): b is Business => !!b && b.isActive);
    }

    try {
      const pool = getPool();
      const res = await pool.query(
        `SELECT b.id, b.slug, b.display_name, b.owner_user_id, b.phone, b.email,
                b.timezone, b.logo_url, b.is_active, b.production_enabled,
                b.daily_recipient_limit, b.created_at, b.updated_at
         FROM businesses b
         INNER JOIN business_members bm ON b.id = bm.business_id
         WHERE bm.user_id = $1 AND b.is_active = true
         ORDER BY b.created_at ASC;`,
        [userId]
      );

      return res.rows.map((r) => this.mapBusinessRow(r));
    } catch (err: any) {
      if (err.code === '42P01') {
        const memberships = Array.from(this.mockMembers.values()).filter((m) => m.userId === userId);
        return memberships
          .map((m) => this.mockBusinesses.get(m.businessId))
          .filter((b): b is Business => !!b && b.isActive);
      }
      throw err;
    }
  }

  /**
   * Creates a new business and automatically establishes the creator as 'owner' in business_members.
   */
  public async create(data: CreateBusinessDTO): Promise<Business> {
    const pool = getPool();
    const client = await pool.connect();

    try {
      await client.query('BEGIN;');

      const insertBizSql = `
        INSERT INTO businesses (
          ${data.id ? 'id,' : ''}
          slug, display_name, owner_user_id, phone, email,
          timezone, logo_url, production_enabled, daily_recipient_limit
        ) VALUES (
          ${data.id ? '$1,' : ''}
          ${data.id ? '$2, $3, $4, $5, $6, $7, $8, $9, $10' : '$1, $2, $3, $4, $5, $6, $7, $8, $9'}
        )
        RETURNING id, slug, display_name, owner_user_id, phone, email,
                  timezone, logo_url, is_active, production_enabled,
                  daily_recipient_limit, created_at, updated_at;
      `;

      const values = data.id
        ? [
            data.id,
            data.slug.trim().toLowerCase(),
            data.displayName.trim(),
            data.ownerUserId,
            data.phone || null,
            data.email || null,
            data.timezone || 'Asia/Kolkata',
            data.logoUrl || null,
            data.productionEnabled ?? false,
            data.dailyRecipientLimit ?? 200,
          ]
        : [
            data.slug.trim().toLowerCase(),
            data.displayName.trim(),
            data.ownerUserId,
            data.phone || null,
            data.email || null,
            data.timezone || 'Asia/Kolkata',
            data.logoUrl || null,
            data.productionEnabled ?? false,
            data.dailyRecipientLimit ?? 200,
          ];

      const bizRes = await client.query(insertBizSql, values);
      const createdBiz = this.mapBusinessRow(bizRes.rows[0]);

      // Automatically assign creator as 'owner'
      await client.query(
        `INSERT INTO business_members (business_id, user_id, role)
         VALUES ($1, $2, 'owner')
         ON CONFLICT (business_id, user_id) DO NOTHING;`,
        [createdBiz.id, data.ownerUserId]
      );

      await client.query('COMMIT;');
      this.setMockBusiness(createdBiz);
      return createdBiz;
    } catch (err: any) {
      await client.query('ROLLBACK;');
      if (err.code === '42P01') {
        const mockBiz: Business = {
          id: data.id || `biz_${Date.now()}`,
          slug: data.slug.trim().toLowerCase(),
          displayName: data.displayName.trim(),
          ownerUserId: data.ownerUserId,
          phone: data.phone || null,
          email: data.email || null,
          timezone: data.timezone || 'Asia/Kolkata',
          logoUrl: data.logoUrl || null,
          isActive: true,
          productionEnabled: data.productionEnabled ?? false,
          dailyRecipientLimit: data.dailyRecipientLimit ?? 200,
          createdAt: new Date(),
          updatedAt: new Date(),
        };
        this.setMockBusiness(mockBiz);
        this.mockMembers.set(`${mockBiz.id}:${data.ownerUserId}`, {
          id: `bm_owner_${mockBiz.id}`,
          businessId: mockBiz.id,
          userId: data.ownerUserId,
          role: 'owner',
          joinedAt: new Date(),
          updatedAt: new Date(),
        });
        return mockBiz;
      }
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Updates business attributes.
   */
  public async update(id: string, data: UpdateBusinessDTO): Promise<Business | null> {
    const pool = getPool();
    const setClauses: string[] = [];
    const values: any[] = [id];
    let paramIndex = 2;

    if (data.displayName !== undefined) {
      setClauses.push(`display_name = $${paramIndex++}`);
      values.push(data.displayName.trim());
    }
    if (data.phone !== undefined) {
      setClauses.push(`phone = $${paramIndex++}`);
      values.push(data.phone);
    }
    if (data.email !== undefined) {
      setClauses.push(`email = $${paramIndex++}`);
      values.push(data.email);
    }
    if (data.timezone !== undefined) {
      setClauses.push(`timezone = $${paramIndex++}`);
      values.push(data.timezone);
    }
    if (data.logoUrl !== undefined) {
      setClauses.push(`logo_url = $${paramIndex++}`);
      values.push(data.logoUrl);
    }
    if (data.isActive !== undefined) {
      setClauses.push(`is_active = $${paramIndex++}`);
      values.push(data.isActive);
    }
    if (data.productionEnabled !== undefined) {
      setClauses.push(`production_enabled = $${paramIndex++}`);
      values.push(data.productionEnabled);
    }
    if (data.dailyRecipientLimit !== undefined) {
      setClauses.push(`daily_recipient_limit = $${paramIndex++}`);
      values.push(data.dailyRecipientLimit);
    }

    if (setClauses.length === 0) return this.findById(id);

    setClauses.push(`updated_at = NOW()`);

    const sql = `
      UPDATE businesses
      SET ${setClauses.join(', ')}
      WHERE id = $1
      RETURNING id, slug, display_name, owner_user_id, phone, email,
                timezone, logo_url, is_active, production_enabled,
                daily_recipient_limit, created_at, updated_at;
    `;

    try {
      const res = await pool.query(sql, values);
      if (res.rows.length === 0) return null;
      const updated = this.mapBusinessRow(res.rows[0]);
      this.setMockBusiness(updated);
      return updated;
    } catch (err: any) {
      if (err.code === '42P01') {
        const existing = this.mockBusinesses.get(id);
        if (!existing) return null;
        if (data.displayName !== undefined) existing.displayName = data.displayName.trim();
        if (data.phone !== undefined) existing.phone = data.phone;
        if (data.email !== undefined) existing.email = data.email;
        if (data.timezone !== undefined) existing.timezone = data.timezone;
        if (data.logoUrl !== undefined) existing.logoUrl = data.logoUrl;
        existing.updatedAt = new Date();
        this.setMockBusiness(existing);
        return existing;
      }
      throw err;
    }
  }

  /**
   * Retrieves a single membership record.
   */
  public async getMember(businessId: string, userId: string): Promise<BusinessMember | null> {
    const mockHit = this.mockMembers.get(`${businessId}:${userId}`);
    if (mockHit) return mockHit;

    try {
      const pool = getPool();
      const res = await pool.query(
        `SELECT id, business_id, user_id, role, invited_by, joined_at, updated_at
         FROM business_members
         WHERE business_id = $1 AND user_id = $2
         LIMIT 1;`,
        [businessId, userId]
      );

      if (res.rows.length === 0) return null;
      return this.mapMemberRow(res.rows[0]);
    } catch (err: any) {
      if (err.code === '42P01') return null;
      throw err;
    }
  }

  /**
   * Lists all members of a business, enriched with user name and email.
   * Sorted with owner(s) first, then admins, then staff.
   */
  public async getMembers(businessId: string): Promise<BusinessMember[]> {
    const mockList = Array.from(this.mockMembers.values()).filter((m) => m.businessId === businessId);
    if (mockList.length > 0) return mockList;

    try {
      const pool = getPool();
      const res = await pool.query(
        `SELECT bm.id, bm.business_id, bm.user_id, bm.role, bm.invited_by, bm.joined_at, bm.updated_at,
                u.name AS user_name, u.email AS user_email
         FROM business_members bm
         LEFT JOIN users u ON bm.user_id = u.id
         WHERE bm.business_id = $1
         ORDER BY CASE bm.role WHEN 'owner' THEN 1 WHEN 'admin' THEN 2 ELSE 3 END, bm.joined_at ASC;`,
        [businessId]
      );

      return res.rows.map((r) => this.mapMemberRow(r));
    } catch (err: any) {
      if (err.code === '42P01') return [];
      throw err;
    }
  }

  /**
   * Counts active owners of a business to prevent demoting or removing the last owner.
   */
  public async getOwnerCount(businessId: string): Promise<number> {
    const mockOwners = Array.from(this.mockMembers.values()).filter(
      (m) => m.businessId === businessId && m.role === 'owner'
    );
    if (mockOwners.length > 0) return mockOwners.length;

    try {
      const pool = getPool();
      const res = await pool.query<{ count: string }>(
        `SELECT COUNT(*) as count
         FROM business_members
         WHERE business_id = $1 AND role = 'owner';`,
        [businessId]
      );
      return parseInt(res.rows[0]?.count || '0', 10);
    } catch (err: any) {
      if (err.code === '42P01') return 1;
      throw err;
    }
  }

  /**
   * Adds a user to a business with an authorized role.
   */
  public async addMember(
    businessId: string,
    userId: string,
    role: BusinessRole = 'staff',
    invitedBy?: string
  ): Promise<BusinessMember> {
    try {
      const pool = getPool();
      const res = await pool.query(
        `INSERT INTO business_members (business_id, user_id, role, invited_by)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (business_id, user_id) DO UPDATE
         SET role = EXCLUDED.role, updated_at = NOW()
         RETURNING id, business_id, user_id, role, invited_by, joined_at, updated_at;`,
        [businessId, userId, role, invitedBy || null]
      );

      const mapped = this.mapMemberRow(res.rows[0]);
      this.mockMembers.set(`${businessId}:${userId}`, mapped);
      return mapped;
    } catch (err: any) {
      if (err.code === '42P01') {
        const mock: BusinessMember = {
          id: `bm_${Date.now()}`,
          businessId,
          userId,
          role,
          invitedBy: invitedBy || null,
          joinedAt: new Date(),
          updatedAt: new Date(),
        };
        this.mockMembers.set(`${businessId}:${userId}`, mock);
        return mock;
      }
      throw err;
    }
  }

  /**
   * Removes a member from a business.
   */
  public async removeMember(businessId: string, userId: string): Promise<boolean> {
    this.mockMembers.delete(`${businessId}:${userId}`);
    try {
      const pool = getPool();
      const res = await pool.query(
        `DELETE FROM business_members
         WHERE business_id = $1 AND user_id = $2;`,
        [businessId, userId]
      );
      return (res.rowCount ?? 0) > 0;
    } catch (err: any) {
      if (err.code === '42P01') return true;
      throw err;
    }
  }

  /**
   * Updates the role of an existing business member.
   */
  public async updateMemberRole(
    businessId: string,
    userId: string,
    role: BusinessRole
  ): Promise<BusinessMember | null> {
    try {
      const pool = getPool();
      const res = await pool.query(
        `UPDATE business_members
         SET role = $3, updated_at = NOW()
         WHERE business_id = $1 AND user_id = $2
         RETURNING id, business_id, user_id, role, invited_by, joined_at, updated_at;`,
        [businessId, userId, role]
      );

      if (res.rows.length === 0) return null;
      const mapped = this.mapMemberRow(res.rows[0]);
      this.mockMembers.set(`${businessId}:${userId}`, mapped);
      return mapped;
    } catch (err: any) {
      if (err.code === '42P01') {
        const existing = this.mockMembers.get(`${businessId}:${userId}`);
        if (!existing) return null;
        existing.role = role;
        existing.updatedAt = new Date();
        return existing;
      }
      throw err;
    }
  }

  /**
   * Creates or replaces an invitation for a business.
   */
  public async createInvitation(data: {
    businessId: string;
    email: string;
    role: 'admin' | 'staff';
    token: string;
    invitedBy: string;
    expiresAt: Date;
  }): Promise<BusinessInvitation> {
    const normalizedEmail = data.email.trim().toLowerCase();

    try {
      const pool = getPool();

      // Revoke any existing pending invitations for this email + business
      await pool.query(
        `UPDATE business_invitations
         SET status = 'revoked', updated_at = NOW()
         WHERE business_id = $1 AND LOWER(email) = $2 AND status = 'pending';`,
        [data.businessId, normalizedEmail]
      );

      const res = await pool.query(
        `INSERT INTO business_invitations (business_id, email, role, token, invited_by, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id, business_id, email, role, token, invited_by, status, expires_at, created_at, updated_at;`,
        [data.businessId, normalizedEmail, data.role, data.token, data.invitedBy, data.expiresAt]
      );

      const inv = this.mapInvitationRow(res.rows[0]);
      this.mockInvitations.set(inv.token, inv);
      return inv;
    } catch (err: any) {
      if (err.code === '42P01') {
        const inv: BusinessInvitation = {
          id: `inv_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`,
          businessId: data.businessId,
          email: normalizedEmail,
          role: data.role,
          token: data.token,
          invitedBy: data.invitedBy,
          status: 'pending',
          expiresAt: data.expiresAt,
          createdAt: new Date(),
          updatedAt: new Date(),
        };
        this.mockInvitations.set(inv.token, inv);
        return inv;
      }
      throw err;
    }
  }

  /**
   * Lists pending invitations for a business.
   */
  public async getPendingInvitations(businessId: string): Promise<BusinessInvitation[]> {
    try {
      const pool = getPool();
      const res = await pool.query(
        `SELECT id, business_id, email, role, token, invited_by, status, expires_at, created_at, updated_at
         FROM business_invitations
         WHERE business_id = $1 AND status = 'pending' AND expires_at > NOW()
         ORDER BY created_at DESC;`,
        [businessId]
      );
      return res.rows.map((r) => this.mapInvitationRow(r));
    } catch (err: any) {
      if (err.code === '42P01') {
        return Array.from(this.mockInvitations.values()).filter(
          (i) => i.businessId === businessId && i.status === 'pending' && i.expiresAt > new Date()
        );
      }
      throw err;
    }
  }

  /**
   * Finds an invitation by its unique secret token.
   */
  public async findInvitationByToken(token: string): Promise<BusinessInvitation | null> {
    const mock = this.mockInvitations.get(token.trim());
    if (mock) return mock;

    try {
      const pool = getPool();
      const res = await pool.query(
        `SELECT id, business_id, email, role, token, invited_by, status, expires_at, created_at, updated_at
         FROM business_invitations
         WHERE token = $1
         LIMIT 1;`,
        [token.trim()]
      );

      if (res.rows.length === 0) return null;
      return this.mapInvitationRow(res.rows[0]);
    } catch (err: any) {
      if (err.code === '42P01') return null;
      throw err;
    }
  }

  /**
   * Revokes a pending invitation.
   */
  public async revokeInvitation(businessId: string, invitationId: string): Promise<boolean> {
    for (const inv of this.mockInvitations.values()) {
      if (inv.id === invitationId && inv.businessId === businessId) {
        inv.status = 'revoked';
        inv.updatedAt = new Date();
        return true;
      }
    }

    try {
      const pool = getPool();
      const res = await pool.query(
        `UPDATE business_invitations
         SET status = 'revoked', updated_at = NOW()
         WHERE id = $1 AND business_id = $2 AND status = 'pending';`,
        [invitationId, businessId]
      );
      return (res.rowCount ?? 0) > 0;
    } catch (err: any) {
      if (err.code === '42P01') return false;
      throw err;
    }
  }

  /**
   * Accepts an invitation in a transactional manner.
   */
  public async acceptInvitation(
    token: string,
    userId: string
  ): Promise<{ businessId: string; role: BusinessRole }> {
    const mock = this.mockInvitations.get(token.trim());
    if (mock) {
      if (mock.status !== 'pending') throw new Error(`INVITATION_NOT_PENDING:${mock.status}`);
      if (mock.expiresAt < new Date()) {
        mock.status = 'expired';
        throw new Error('INVITATION_EXPIRED');
      }
      mock.status = 'accepted';
      mock.updatedAt = new Date();
      await this.addMember(mock.businessId, userId, mock.role, mock.invitedBy);
      return { businessId: mock.businessId, role: mock.role };
    }

    const pool = getPool();
    const client = await pool.connect();

    try {
      await client.query('BEGIN;');

      const invRes = await client.query(
        `SELECT id, business_id, email, role, token, invited_by, status, expires_at
         FROM business_invitations
         WHERE token = $1
         FOR UPDATE;`,
        [token.trim()]
      );

      if (invRes.rows.length === 0) {
        throw new Error('INVITATION_NOT_FOUND');
      }

      const inv = invRes.rows[0];

      if (inv.status !== 'pending') {
        throw new Error(`INVITATION_NOT_PENDING:${inv.status}`);
      }

      if (new Date(inv.expires_at) < new Date()) {
        await client.query(
          `UPDATE business_invitations SET status = 'expired', updated_at = NOW() WHERE id = $1;`,
          [inv.id]
        );
        throw new Error('INVITATION_EXPIRED');
      }

      // Add user to business_members
      await client.query(
        `INSERT INTO business_members (business_id, user_id, role, invited_by)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (business_id, user_id) DO UPDATE
         SET role = EXCLUDED.role, updated_at = NOW();`,
        [inv.business_id, userId, inv.role, inv.invited_by]
      );

      // Mark invitation accepted
      await client.query(
        `UPDATE business_invitations
         SET status = 'accepted', updated_at = NOW()
         WHERE id = $1;`,
        [inv.id]
      );

      await client.query('COMMIT;');
      return { businessId: inv.business_id, role: inv.role as BusinessRole };
    } catch (e) {
      await client.query('ROLLBACK;');
      throw e;
    } finally {
      client.release();
    }
  }

  private mapBusinessRow(row: any): Business {
    return {
      id: row.id,
      slug: row.slug,
      displayName: row.display_name,
      ownerUserId: row.owner_user_id,
      phone: row.phone,
      email: row.email,
      timezone: row.timezone,
      logoUrl: row.logo_url,
      isActive: row.is_active,
      productionEnabled: row.production_enabled,
      dailyRecipientLimit: Number(row.daily_recipient_limit),
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  private mapMemberRow(row: any): BusinessMember {
    return {
      id: row.id,
      businessId: row.business_id,
      userId: row.user_id,
      role: row.role as BusinessRole,
      invitedBy: row.invited_by,
      joinedAt: row.joined_at,
      updatedAt: row.updated_at,
      name: row.user_name || undefined,
      email: row.user_email || undefined,
    };
  }

  private mapInvitationRow(row: any): BusinessInvitation {
    return {
      id: row.id,
      businessId: row.business_id,
      email: row.email,
      role: row.role as 'admin' | 'staff',
      token: row.token,
      invitedBy: row.invited_by,
      status: row.status as InvitationStatus,
      expiresAt: row.expires_at,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }
}

export const businessStore = new BusinessStore();
