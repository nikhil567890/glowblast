import { PoolClient } from 'pg';
import { getPool } from '../db/pool';
import { WhatsAppTemplate, TemplateApprovalStatus, MetaTemplateStatus } from '../types/template';

export const SEED_TEMPLATES: WhatsAppTemplate[] = [
  {
    id: 'tpl_hello_world',
    name: 'hello_world',
    displayName: 'Meta Test Default (Hello World)',
    description: 'Official Meta WhatsApp Cloud API default test template (no parameters). Pre-approved on all Meta test numbers.',
    category: 'UTILITY',
    language: 'en_US',
    status: 'approved',
    metaStatus: 'APPROVED',
    body: 'Hello World',
    variables: [],
    mode: 'test',
    wabaId: '1633948435034571',
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
  },
  {
    id: 'tpl_birthday',
    name: 'birthday_offer',
    displayName: 'Birthday Pampering',
    description: 'Celebratory birthday greeting with personalized 25% discount. (Draft - requires Meta submission/approval)',
    category: 'MARKETING',
    language: 'en_US',
    status: 'draft',
    metaStatus: 'NOT_SUBMITTED',
    body: '🎂 Happy Birthday month, {name}! Celebrate your special day with our rejuvenating therapy at {business_name}. Enjoy 25% OFF on any 90-minute treatment this month. Reply BOOK to reserve!',
    variables: ['name', 'business_name'],
    exampleValues: {
      name: 'Nikhil',
      business_name: 'Luxspa',
    },
    mode: 'test',
    createdAt: '2026-02-01T00:00:00.000Z',
    updatedAt: '2026-02-01T00:00:00.000Z',
  },
  {
    id: 'tpl_diwali',
    name: 'diwali_offer',
    displayName: 'Diwali Festive Radiance',
    description: 'Festive radiance offer with flat 35% discount. (Draft - requires Meta submission/approval)',
    category: 'MARKETING',
    language: 'en_US',
    status: 'draft',
    metaStatus: 'NOT_SUBMITTED',
    body: '✨ Sparkle & Glow this Diwali! Indulge in our Festive Radiance Ritual at {business_name} with flat 35% OFF until Diwali eve. Treat yourself or gift a loved one! Reply YES to book.',
    variables: ['business_name'],
    exampleValues: {
      business_name: 'Luxspa & Wellness',
    },
    mode: 'test',
    wabaId: '1633948435034571',
    createdAt: '2026-02-01T00:00:00.000Z',
    updatedAt: '2026-02-01T00:00:00.000Z',
  },
  {
    id: 'tpl_reminder',
    name: 'appointment_reminder',
    displayName: 'Appointment Reminder',
    description: 'Pre-visit confirmation and timing reminder. (Draft - requires Meta submission/approval)',
    category: 'UTILITY',
    language: 'en_US',
    status: 'draft',
    metaStatus: 'NOT_SUBMITTED',
    body: '🌸 Hi {name}, this is a gentle reminder for your upcoming appointment at {business_name}. Please arrive 10 minutes early to enjoy our warm herbal welcome tea.',
    variables: ['name', 'business_name'],
    exampleValues: {
      name: 'Ananya',
      business_name: 'Our Spa & Wellness',
    },
    mode: 'test',
    createdAt: '2026-02-01T00:00:00.000Z',
    updatedAt: '2026-02-01T00:00:00.000Z',
  },
  {
    id: 'tpl_vip_draft',
    name: 'vip_exclusive_access',
    displayName: 'VIP Exclusive Access (Draft)',
    description: 'Local draft template awaiting finalization. Cannot be dispatched until submitted and approved by Meta.',
    category: 'MARKETING',
    language: 'en_US',
    status: 'draft',
    metaStatus: 'NOT_SUBMITTED',
    body: '✨ Exclusive VIP invitation for {name} from {business_name}. Enjoy priority booking!',
    variables: ['name', 'business_name'],
    mode: 'test',
    createdAt: '2026-03-01T00:00:00.000Z',
    updatedAt: '2026-03-01T00:00:00.000Z',
  },
  {
    id: 'tpl_festival_pending',
    name: 'festival_super_sale',
    displayName: 'Festival Super Sale (Pending Meta Approval)',
    description: 'Submitted to Meta WhatsApp Business Platform and currently under review. Cannot be dispatched until approved.',
    category: 'MARKETING',
    language: 'en_US',
    status: 'pending_approval',
    metaStatus: 'PENDING',
    body: '🎉 Grand Festive Sale at {business_name}! Enjoy 40% OFF all therapies this weekend, {name}!',
    variables: ['business_name', 'name'],
    mode: 'test',
    createdAt: '2026-03-05T00:00:00.000Z',
    updatedAt: '2026-03-05T00:00:00.000Z',
  },
];

export class TemplateStore {
  private seeded = false;

  private mapRow(row: any): WhatsAppTemplate {
    let variables: string[] = [];
    if (Array.isArray(row.variables)) {
      variables = row.variables;
    } else if (typeof row.variables === 'string') {
      try {
        variables = JSON.parse(row.variables);
      } catch {
        variables = [];
      }
    }

    let exampleValues: Record<string, string> | undefined = undefined;
    if (row.example_values) {
      if (typeof row.example_values === 'object') {
        exampleValues = row.example_values;
      } else if (typeof row.example_values === 'string') {
        try {
          exampleValues = JSON.parse(row.example_values);
        } catch {
          exampleValues = undefined;
        }
      }
    }

    return {
      id: row.id,
      name: row.name,
      displayName: row.display_name,
      description: row.description || undefined,
      category: row.category,
      language: row.language,
      status: row.status as TemplateApprovalStatus,
      metaStatus: row.meta_status as MetaTemplateStatus,
      metaTemplateId: row.meta_template_id || undefined,
      body: row.body,
      variables,
      exampleValues,
      wabaId: row.waba_id || undefined,
      mode: (row.mode as 'test' | 'production') || 'test',
      lastSyncedAt: row.last_synced_at ? new Date(row.last_synced_at).toISOString() : undefined,
      createdAt: new Date(row.created_at).toISOString(),
      updatedAt: new Date(row.updated_at).toISOString(),
    };
  }

  /**
   * Seeds default templates idempotently into PostgreSQL.
   * Never overwrites or replaces an approved Meta template or existing record.
   */
  public async seedDefaults(): Promise<void> {
    if (this.seeded) return;
    const pool = getPool();

    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        for (const tpl of SEED_TEMPLATES) {
          await pool.query(
            `INSERT INTO whatsapp_templates (
              id, name, display_name, description, category, language,
              status, meta_status, body, variables, example_values,
              waba_id, mode, created_at, updated_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, NOW(), NOW())
            ON CONFLICT (id) DO NOTHING;`,
            [
              tpl.id,
              tpl.name,
              tpl.displayName,
              tpl.description || null,
              tpl.category,
              tpl.language,
              tpl.status,
              tpl.metaStatus,
              tpl.body,
              JSON.stringify(tpl.variables || []),
              tpl.exampleValues ? JSON.stringify(tpl.exampleValues) : null,
              tpl.wabaId || null,
              tpl.mode || 'test',
            ]
          );
        }
        this.seeded = true;
        return;
      } catch (err: any) {
        if (attempt === 2) throw err;
        await new Promise((r) => setTimeout(r, 1000 * (attempt + 1)));
      }
    }
  }

  /**
   * Retrieves all templates from PostgreSQL, optionally filtered by mode ('test' | 'production').
   */
  public async getAll(mode?: 'test' | 'production'): Promise<WhatsAppTemplate[]> {
    await this.seedDefaults();
    const pool = getPool();

    let query = `SELECT * FROM whatsapp_templates`;
    const params: any[] = [];

    if (mode === 'production') {
      query += ` WHERE mode = 'production'`;
    } else if (mode === 'test') {
      query += ` WHERE mode = 'test'`;
    }
    query += ` ORDER BY created_at ASC;`;

    const res = await pool.query(query, params);
    return res.rows.map((r) => this.mapRow(r));
  }

  /**
   * Retrieves a template by its primary key ID.
   */
  public async getById(id: string): Promise<WhatsAppTemplate | undefined> {
    await this.seedDefaults();
    const pool = getPool();

    const res = await pool.query(
      `SELECT * FROM whatsapp_templates WHERE id = $1 LIMIT 1;`,
      [id.trim()]
    );

    if (res.rows.length === 0) return undefined;
    return this.mapRow(res.rows[0]);
  }

  /**
   * Retrieves a template by Meta name, strictly respecting mode isolation.
  /**
   * Retrieves a template by Meta name, strictly respecting mode isolation.
   */
  public async getByName(name: string, mode?: 'test' | 'production'): Promise<WhatsAppTemplate | undefined> {
    return this.getByNameAndMode(name, mode);
  }

  /**
   * Retrieves a template by Meta name, mode, and optional language.
   */
  public async getByNameAndMode(
    name: string,
    mode?: 'test' | 'production',
    language?: string
  ): Promise<WhatsAppTemplate | undefined> {
    await this.seedDefaults();
    const pool = getPool();

    let query = `SELECT * FROM whatsapp_templates WHERE LOWER(name) = LOWER($1)`;
    const params: any[] = [name.trim()];

    if (mode === 'production') {
      params.push('production');
      query += ` AND mode = $${params.length}`;
    } else if (mode === 'test') {
      params.push('test');
      query += ` AND mode = $${params.length}`;
    }

    if (language && language.trim().length > 0) {
      params.push(language.trim());
      query += ` AND LOWER(language) = LOWER($${params.length})`;
    }

    query += ` ORDER BY updated_at DESC LIMIT 1;`;

    const res = await pool.query(query, params);
    if (res.rows.length === 0) return undefined;
    return this.mapRow(res.rows[0]);
  }

  /**
   * Retrieves a template by ID or Meta name, strictly respecting mode isolation and optional language.
   * In production mode, sandbox templates can NEVER be returned.
   */
  public async findByIdOrName(
    idOrName: string,
    mode?: 'test' | 'production',
    language?: string
  ): Promise<WhatsAppTemplate | undefined> {
    await this.seedDefaults();
    const pool = getPool();
    const clean = idOrName.trim();

    let query = `SELECT * FROM whatsapp_templates WHERE (id = $1 OR LOWER(name) = LOWER($1))`;
    const params: any[] = [clean];

    if (mode === 'production') {
      params.push('production');
      query += ` AND mode = $${params.length}`;
    } else if (mode === 'test') {
      params.push('test');
      query += ` AND mode = $${params.length}`;
    }

    if (language && language.trim().length > 0) {
      params.push(language.trim());
      query += ` AND LOWER(language) = LOWER($${params.length})`;
    }

    query += ` ORDER BY (CASE WHEN id = $1 THEN 0 ELSE 1 END), updated_at DESC LIMIT 1;`;

    const res = await pool.query(query, params);
    if (res.rows.length === 0) return undefined;
    return this.mapRow(res.rows[0]);
  }

  /**
   * Alias for findByIdOrName.
   */
  public async get(idOrName: string, mode?: 'test' | 'production'): Promise<WhatsAppTemplate | undefined> {
    return this.findByIdOrName(idOrName, mode);
  }

  /**
   * Retrieves all approved templates, optionally filtered by mode.
   */
  public async getApproved(mode?: 'test' | 'production'): Promise<WhatsAppTemplate[]> {
    await this.seedDefaults();
    const pool = getPool();

    let query = `SELECT * FROM whatsapp_templates WHERE status = 'approved'`;
    const params: any[] = [];

    if (mode === 'production') {
      query += ` AND mode = 'production'`;
    } else if (mode === 'test') {
      query += ` AND mode = 'test'`;
    }
    query += ` ORDER BY created_at ASC;`;

    const res = await pool.query(query, params);
    return res.rows.map((r) => this.mapRow(r));
  }

  /**
   * Inserts or upserts a template into PostgreSQL.
   * Resolves existing row by (LOWER(name), mode, language) to avoid unique constraint collisions
   * across different ID generation schemes.
   */
  public async create(tpl: WhatsAppTemplate): Promise<WhatsAppTemplate> {
    const pool = getPool();

    const tplLanguage = tpl.language || 'en_US';
    const tplMode = tpl.mode || 'test';

    // Check if an existing row matches (LOWER(name), mode, language) under any ID
    const existingRow = await pool.query<{ id: string }>(
      `SELECT id FROM whatsapp_templates WHERE LOWER(name) = LOWER($1) AND mode = $2 AND LOWER(language) = LOWER($3) LIMIT 1;`,
      [tpl.name.trim(), tplMode, tplLanguage.trim()]
    );

    const effectiveId = existingRow.rows.length > 0 ? existingRow.rows[0].id : tpl.id;

    const res = await pool.query(
      `INSERT INTO whatsapp_templates (
        id, name, display_name, description, category, language,
        status, meta_status, meta_template_id, body, variables, example_values,
        waba_id, mode, last_synced_at, created_at, updated_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, NOW())
      ON CONFLICT (id) DO UPDATE SET
        name = EXCLUDED.name,
        display_name = EXCLUDED.display_name,
        description = COALESCE(EXCLUDED.description, whatsapp_templates.description),
        category = EXCLUDED.category,
        language = EXCLUDED.language,
        status = EXCLUDED.status,
        meta_status = EXCLUDED.meta_status,
        meta_template_id = COALESCE(EXCLUDED.meta_template_id, whatsapp_templates.meta_template_id),
        body = EXCLUDED.body,
        variables = EXCLUDED.variables,
        example_values = COALESCE(EXCLUDED.example_values, whatsapp_templates.example_values),
        waba_id = COALESCE(EXCLUDED.waba_id, whatsapp_templates.waba_id),
        mode = EXCLUDED.mode,
        last_synced_at = COALESCE(EXCLUDED.last_synced_at, whatsapp_templates.last_synced_at),
        updated_at = NOW()
      RETURNING *;`,
      [
        effectiveId,
        tpl.name,
        tpl.displayName,
        tpl.description || null,
        tpl.category,
        tplLanguage,
        tpl.status,
        tpl.metaStatus,
        tpl.metaTemplateId || null,
        tpl.body,
        JSON.stringify(tpl.variables || []),
        tpl.exampleValues ? JSON.stringify(tpl.exampleValues) : null,
        tpl.wabaId || null,
        tplMode,
        tpl.lastSyncedAt ? new Date(tpl.lastSyncedAt) : null,
        tpl.createdAt ? new Date(tpl.createdAt) : new Date(),
      ]
    );

    return this.mapRow(res.rows[0]);
  }

  /**
   * Updates an existing template by ID.
   */
  public async update(id: string, updates: Partial<WhatsAppTemplate>): Promise<WhatsAppTemplate | undefined> {
    const existing = await this.getById(id);
    if (!existing) return undefined;

    const merged: WhatsAppTemplate = {
      ...existing,
      ...updates,
      updatedAt: new Date().toISOString(),
    };

    return this.create(merged);
  }

  /**
   * Updates template approval and meta statuses.
   */
  public async updateStatus(
    id: string,
    status: TemplateApprovalStatus,
    metaStatus?: MetaTemplateStatus
  ): Promise<WhatsAppTemplate | undefined> {
    const pool = getPool();
    const res = await pool.query(
      `UPDATE whatsapp_templates
       SET status = $2,
           meta_status = COALESCE($3, meta_status),
           updated_at = NOW()
       WHERE id = $1
       RETURNING *;`,
      [id.trim(), status, metaStatus || null]
    );

    if (res.rows.length === 0) return undefined;
    return this.mapRow(res.rows[0]);
  }

  /**
   * Deletes a template by ID.
   */
  public async delete(id: string): Promise<boolean> {
    const pool = getPool();
    const res = await pool.query(
      `DELETE FROM whatsapp_templates WHERE id = $1;`,
      [id.trim()]
    );
    return (res.rowCount ?? 0) > 0;
  }

  /**
   * Clears custom templates and resets defaults (used in test fixtures).
   */
  public async clear(): Promise<void> {
    const pool = getPool();
    await pool.query('DELETE FROM whatsapp_templates;');
    this.seeded = false;
    await this.seedDefaults();
  }
}

export const templateStore = new TemplateStore();
