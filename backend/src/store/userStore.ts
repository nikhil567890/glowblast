import { PoolClient } from 'pg';
import { getPool } from '../db/pool';
import { User, SafeUser, OtpRecord } from '../types/auth';

export class UserStore {
  public async findByEmail(email: string): Promise<User | undefined> {
    const normalized = email.trim().toLowerCase();
    const pool = getPool();
    const res = await pool.query<{
      id: string;
      email: string;
      password_hash: string;
      name: string;
      business_name: string | null;
      phone: string | null;
      email_verified: boolean;
      created_at: Date;
      updated_at: Date;
      last_login_at: Date | null;
    }>(
      `SELECT id, email, password_hash, name, business_name, phone, email_verified,
              created_at, updated_at, last_login_at
       FROM users
       WHERE LOWER(email) = $1
       LIMIT 1;`,
      [normalized]
    );

    if (res.rows.length === 0) return undefined;
    const row = res.rows[0];

    return {
      id: row.id,
      name: row.name,
      email: row.email,
      passwordHash: row.password_hash,
      businessName: row.business_name || undefined,
      phone: row.phone || undefined,
      emailVerified: row.email_verified,
      createdAt: row.created_at.toISOString(),
      updatedAt: row.updated_at.toISOString(),
      lastLoginAt: row.last_login_at?.toISOString() || undefined,
    };
  }

  public async findById(id: string): Promise<User | undefined> {
    const pool = getPool();
    const res = await pool.query<{
      id: string;
      email: string;
      password_hash: string;
      name: string;
      business_name: string | null;
      phone: string | null;
      email_verified: boolean;
      created_at: Date;
      updated_at: Date;
      last_login_at: Date | null;
    }>(
      `SELECT id, email, password_hash, name, business_name, phone, email_verified,
              created_at, updated_at, last_login_at
       FROM users
       WHERE id = $1
       LIMIT 1;`,
      [id]
    );

    if (res.rows.length === 0) return undefined;
    const row = res.rows[0];

    return {
      id: row.id,
      name: row.name,
      email: row.email,
      passwordHash: row.password_hash,
      businessName: row.business_name || undefined,
      phone: row.phone || undefined,
      emailVerified: row.email_verified,
      createdAt: row.created_at.toISOString(),
      updatedAt: row.updated_at.toISOString(),
      lastLoginAt: row.last_login_at?.toISOString() || undefined,
    };
  }

  public async saveUser(user: User): Promise<User> {
    const pool = getPool();
    await pool.query(
      `INSERT INTO users (
        id, email, password_hash, name, business_name, phone, email_verified,
        last_login_at, created_at, updated_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        password_hash = EXCLUDED.password_hash,
        name = EXCLUDED.name,
        business_name = EXCLUDED.business_name,
        phone = EXCLUDED.phone,
        email_verified = EXCLUDED.email_verified,
        last_login_at = EXCLUDED.last_login_at,
        updated_at = NOW();`,
      [
        user.id,
        user.email.toLowerCase(),
        user.passwordHash,
        user.name,
        user.businessName || null,
        user.phone || null,
        user.emailVerified,
        user.lastLoginAt ? new Date(user.lastLoginAt) : null,
        user.createdAt ? new Date(user.createdAt) : new Date(),
        user.updatedAt ? new Date(user.updatedAt) : new Date(),
      ]
    );

    return user;
  }

  public async saveOtp(record: OtpRecord): Promise<void> {
    const pool = getPool();
    await pool.query(
      `INSERT INTO auth_otps (
        email, name, password_hash, otp_hash, business_name, phone,
        attempts, expires_at, last_requested_at, created_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      ON CONFLICT (email) DO UPDATE SET
        name = EXCLUDED.name,
        password_hash = EXCLUDED.password_hash,
        otp_hash = EXCLUDED.otp_hash,
        business_name = EXCLUDED.business_name,
        phone = EXCLUDED.phone,
        attempts = EXCLUDED.attempts,
        expires_at = EXCLUDED.expires_at,
        last_requested_at = EXCLUDED.last_requested_at,
        created_at = EXCLUDED.created_at;`,
      [
        record.email.toLowerCase(),
        record.name,
        record.passwordHash,
        record.otpHash,
        record.businessName || null,
        record.phone || null,
        record.attempts,
        new Date(record.expiresAt),
        new Date(record.lastRequestedAt),
        new Date(record.createdAt),
      ]
    );
  }

  public async getOtp(email: string): Promise<OtpRecord | undefined> {
    const pool = getPool();
    const res = await pool.query<{
      email: string;
      name: string;
      password_hash: string;
      otp_hash: string;
      business_name: string | null;
      phone: string | null;
      attempts: number;
      expires_at: Date;
      last_requested_at: Date;
      created_at: Date;
    }>(
      `SELECT email, name, password_hash, otp_hash, business_name, phone,
              attempts, expires_at, last_requested_at, created_at
       FROM auth_otps
       WHERE email = $1
       LIMIT 1;`,
      [email.toLowerCase()]
    );

    if (res.rows.length === 0) return undefined;
    const row = res.rows[0];

    // Check expiration
    if (Date.now() > row.expires_at.getTime()) {
      await this.deleteOtp(email);
      return undefined;
    }

    return {
      email: row.email,
      name: row.name,
      passwordHash: row.password_hash,
      otpHash: row.otp_hash,
      businessName: row.business_name || undefined,
      phone: row.phone || undefined,
      attempts: row.attempts,
      expiresAt: row.expires_at.getTime(),
      lastRequestedAt: row.last_requested_at.getTime(),
      createdAt: row.created_at.getTime(),
    };
  }

  public async deleteOtp(email: string): Promise<void> {
    const pool = getPool();
    await pool.query('DELETE FROM auth_otps WHERE email = $1;', [email.toLowerCase()]);
  }

  public async incrementOtpAttempts(email: string): Promise<number> {
    const pool = getPool();
    const res = await pool.query<{ attempts: number }>(
      `UPDATE auth_otps
       SET attempts = attempts + 1
       WHERE email = $1
       RETURNING attempts;`,
      [email.toLowerCase()]
    );

    return res.rows[0]?.attempts || 0;
  }

  public toSafeUser(user: User): SafeUser {
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const { passwordHash, ...safe } = user;
    return safe;
  }

  public async clear(): Promise<void> {
    const pool = getPool();
    await pool.query('DELETE FROM auth_otps;');
    await pool.query("DELETE FROM users WHERE email LIKE '%test%' OR email LIKE '%mock%';");
  }
}

export const userStore = new UserStore();
