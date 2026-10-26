import { getPool } from '../db/pool';
import {
  WabaConnectionMode,
  StoredWabaConnectionRecord,
  CreateWabaConnectionInput,
  SafeWabaConnectionInfo,
} from '../types/wabaConnection';
import { encryptWabaToken } from '../utils/tokenEncryption';

export class WabaConnectionStore {
  // In-memory fallback map for test isolation or pre-migration fallback
  private mockConnections: Map<string, StoredWabaConnectionRecord> = new Map();

  /**
   * Resets in-memory mock state (for unit testing).
   */
  public clear(): void {
    this.mockConnections.clear();
  }

  /**
   * Directly sets a mock connection in memory (useful for isolated unit/integration tests).
   */
  public setMockConnection(conn: StoredWabaConnectionRecord): void {
    this.mockConnections.set(`${conn.businessId}:${conn.mode}`, conn);
  }

  /**
   * Finds the active WABA connection for a verified business and mode.
   */
  public async getActiveConnection(
    businessId: string,
    mode: WabaConnectionMode = 'production'
  ): Promise<StoredWabaConnectionRecord | null> {
    const mockKey = `${businessId}:${mode}`;
    const mockHit = this.mockConnections.get(mockKey);
    if (mockHit && mockHit.isActive) {
      return mockHit;
    }

    try {
      const pool = getPool();
      const res = await pool.query<{
        id: string;
        business_id: string;
        waba_id: string;
        phone_number_id: string;
        display_number: string | null;
        mode: WabaConnectionMode;
        is_active: boolean;
        encrypted_access_token: string;
        token_iv: string;
        token_tag: string;
        key_id: string | null;
        meta_app_id: string | null;
        verified_name: string | null;
        quality_rating: string | null;
        code_verification_status: string | null;
        created_at: Date;
        updated_at: Date;
      }>(
        `SELECT id, business_id, waba_id, phone_number_id, display_number,
                mode, is_active, encrypted_access_token, token_iv, token_tag, key_id,
                meta_app_id, verified_name, quality_rating, code_verification_status,
                created_at, updated_at
         FROM business_waba_connections
         WHERE business_id = $1 AND mode = $2 AND is_active = true
         ORDER BY updated_at DESC
         LIMIT 1;`,
        [businessId, mode]
      );

      if (res.rows.length === 0) {
        return null;
      }

      const r = res.rows[0];
      return {
        id: r.id,
        businessId: r.business_id,
        wabaId: r.waba_id,
        phoneNumberId: r.phone_number_id,
        displayNumber: r.display_number || undefined,
        mode: r.mode,
        isActive: r.is_active,
        encryptedAccessToken: r.encrypted_access_token,
        tokenIv: r.token_iv,
        tokenTag: r.token_tag,
        keyId: r.key_id || undefined,
        metaAppId: r.meta_app_id || undefined,
        verifiedName: r.verified_name || undefined,
        qualityRating: r.quality_rating || undefined,
        codeVerificationStatus: r.code_verification_status || undefined,
        createdAt: r.created_at,
        updatedAt: r.updated_at,
      };
    } catch (err: any) {
      if (err.code === '42P01') {
        // Table business_waba_connections does not exist yet (pre-migration)
        return null;
      }
      console.error('[WabaConnectionStore] Failed to query active connection:', err.message);
      return null;
    }
  }

  /**
   * Resolves connection by receiving Meta phone_number_id.
   * Essential for tenant-isolated webhook routing.
   */
  public async findByPhoneNumberId(
    phoneNumberId: string,
    mode?: WabaConnectionMode
  ): Promise<StoredWabaConnectionRecord | null> {
    // Check in-memory mocks
    for (const conn of this.mockConnections.values()) {
      if (
        conn.phoneNumberId === phoneNumberId &&
        conn.isActive &&
        (!mode || conn.mode === mode)
      ) {
        return conn;
      }
    }

    try {
      const pool = getPool();
      let query = `
        SELECT id, business_id, waba_id, phone_number_id, display_number,
               mode, is_active, encrypted_access_token, token_iv, token_tag, key_id,
               meta_app_id, verified_name, quality_rating, code_verification_status,
               created_at, updated_at
        FROM business_waba_connections
        WHERE phone_number_id = $1 AND is_active = true
      `;
      const params: any[] = [phoneNumberId];

      if (mode) {
        query += ` AND mode = $2`;
        params.push(mode);
      }
      query += ` ORDER BY updated_at DESC LIMIT 1;`;

      const res = await pool.query(query, params);
      if (res.rows.length === 0) {
        return null;
      }

      const r = res.rows[0];
      return {
        id: r.id,
        businessId: r.business_id,
        wabaId: r.waba_id,
        phoneNumberId: r.phone_number_id,
        displayNumber: r.display_number || undefined,
        mode: r.mode,
        isActive: r.is_active,
        encryptedAccessToken: r.encrypted_access_token,
        tokenIv: r.token_iv,
        tokenTag: r.token_tag,
        keyId: r.key_id || undefined,
        metaAppId: r.meta_app_id || undefined,
        verifiedName: r.verified_name || undefined,
        qualityRating: r.quality_rating || undefined,
        codeVerificationStatus: r.code_verification_status || undefined,
        createdAt: r.created_at,
        updatedAt: r.updated_at,
      };
    } catch (err: any) {
      if (err.code === '42P01') {
        return null;
      }
      console.error('[WabaConnectionStore] Failed to query by phone_number_id:', err.message);
      return null;
    }
  }

  /**
   * Encrypts and securely persists a WABA connection for a business.
   * NEVER stores raw access tokens in plaintext.
   */
  public async saveConnection(
    input: CreateWabaConnectionInput,
    options?: { customEncryptionKey?: string }
  ): Promise<StoredWabaConnectionRecord> {
    const mode = input.mode || 'production';

    // 1. Authenticated AES-256-GCM encryption with tenant-binding (AAD = businessId)
    const encryptedMaterial = encryptWabaToken(input.plainAccessToken, {
      customKey: options?.customEncryptionKey,
      aad: input.businessId,
    });

    const now = new Date();
    const mockRecord: StoredWabaConnectionRecord = {
      id: `waba_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
      businessId: input.businessId,
      wabaId: input.wabaId,
      phoneNumberId: input.phoneNumberId,
      displayNumber: input.displayNumber,
      mode,
      isActive: true,
      encryptedAccessToken: encryptedMaterial.encryptedAccessToken,
      tokenIv: encryptedMaterial.tokenIv,
      tokenTag: encryptedMaterial.tokenTag,
      keyId: encryptedMaterial.keyId,
      metaAppId: input.metaAppId,
      verifiedName: input.verifiedName,
      qualityRating: input.qualityRating || 'UNKNOWN',
      codeVerificationStatus: input.codeVerificationStatus,
      createdAt: now,
      updatedAt: now,
    };

    try {
      const pool = getPool();

      // Deactivate any existing active connection for this business & mode
      await pool.query(
        `UPDATE business_waba_connections
         SET is_active = false, updated_at = NOW()
         WHERE business_id = $1 AND mode = $2 AND is_active = true;`,
        [input.businessId, mode]
      );

      // Insert new connection record
      const insertRes = await pool.query<{ id: string; created_at: Date; updated_at: Date }>(
        `INSERT INTO business_waba_connections (
           business_id, waba_id, phone_number_id, display_number, mode, is_active,
           encrypted_access_token, token_iv, token_tag, key_id,
           meta_app_id, verified_name, quality_rating, code_verification_status,
           created_at, updated_at
         )
         VALUES ($1, $2, $3, $4, $5, true, $6, $7, $8, $9, $10, $11, $12, $13, NOW(), NOW())
         RETURNING id, created_at, updated_at;`,
        [
          input.businessId,
          input.wabaId,
          input.phoneNumberId,
          input.displayNumber || null,
          mode,
          encryptedMaterial.encryptedAccessToken,
          encryptedMaterial.tokenIv,
          encryptedMaterial.tokenTag,
          encryptedMaterial.keyId || 'v1',
          input.metaAppId || null,
          input.verifiedName || null,
          input.qualityRating || 'UNKNOWN',
          input.codeVerificationStatus || null,
        ]
      );

      mockRecord.id = insertRes.rows[0].id;
      mockRecord.createdAt = insertRes.rows[0].created_at;
      mockRecord.updatedAt = insertRes.rows[0].updated_at;
    } catch (err: any) {
      if (err.code === '42P01') {
        // Fallback for in-memory / pre-migration testing
        this.mockConnections.set(`${input.businessId}:${mode}`, mockRecord);
        return mockRecord;
      }
      throw err;
    }

    this.mockConnections.set(`${input.businessId}:${mode}`, mockRecord);
    return mockRecord;
  }

  /**
   * Deactivates a business's active WABA connection for a mode.
   */
  public async deactivateConnection(
    businessId: string,
    mode: WabaConnectionMode = 'production'
  ): Promise<boolean> {
    const mockKey = `${businessId}:${mode}`;
    const mockConn = this.mockConnections.get(mockKey);
    if (mockConn) {
      mockConn.isActive = false;
    }

    try {
      const pool = getPool();
      const res = await pool.query(
        `UPDATE business_waba_connections
         SET is_active = false, updated_at = NOW()
         WHERE business_id = $1 AND mode = $2 AND is_active = true;`,
        [businessId, mode]
      );
      return (res.rowCount ?? 0) > 0;
    } catch (err: any) {
      if (err.code === '42P01') {
        return mockConn !== undefined;
      }
      console.error('[WabaConnectionStore] Failed to deactivate connection:', err.message);
      return false;
    }
  }

  /**
   * Retrieves sanitized WABA connection information for a business.
   * EXPLICIT SECURITY GUARANTEE: Never leaks encrypted or raw access tokens, IVs, or auth tags.
   */
  public async getSafeConnection(
    businessId: string,
    mode: WabaConnectionMode = 'production'
  ): Promise<SafeWabaConnectionInfo | null> {
    const conn = await this.getActiveConnection(businessId, mode);
    if (!conn) {
      return null;
    }

    return {
      id: conn.id,
      businessId: conn.businessId,
      wabaId: conn.wabaId,
      phoneNumberId: conn.phoneNumberId,
      displayNumber: conn.displayNumber,
      mode: conn.mode,
      isActive: conn.isActive,
      verifiedName: conn.verifiedName,
      qualityRating: conn.qualityRating,
      createdAt: conn.createdAt.toISOString(),
      updatedAt: conn.updatedAt.toISOString(),
    };
  }
}

export const wabaConnectionStore = new WabaConnectionStore();
