import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { getPool } from '../db/pool';
import { requireAuth, requireBusinessMembership, INITIAL_BUSINESS_ID } from '../middleware/authMiddleware';
import { normalizeWhatsAppPhone } from '../utils/phone';

const router = Router();

const bulkDeleteSchema = z.object({
  customerIds: z
    .array(z.string().min(1))
    .min(1, 'At least one customer ID is required')
    .max(500, 'Maximum 500 customers per batch'),
});

const bulkImportCustomerSchema = z.object({
  customers: z.array(
    z.object({
      id: z.string().optional(),
      name: z.string().min(1, 'Name is required'),
      phone: z.string().min(10, 'Valid phone is required'),
    })
  ).min(1).max(1000, 'Maximum 1000 customers per import'),
});

/**
 * GET /api/customers
 * Lists customers belonging to the authenticated business.
 */
router.get('/', requireAuth, requireBusinessMembership(), async (req: Request, res: Response) => {
  const pool = getPool();
  const businessId = req.business!.id;

  try {
    let result: {
      rows: Array<{
        id: string;
        normalized_phone: string;
        display_name: string;
        created_at: Date;
        updated_at: Date;
      }>;
    };
    try {
      result = await pool.query<{
        id: string;
        normalized_phone: string;
        display_name: string;
        created_at: Date;
        updated_at: Date;
      }>(
        `SELECT id, normalized_phone, display_name, created_at, updated_at
         FROM customers
         WHERE business_id = $1 OR (business_id IS NULL AND $1 = $2)
         ORDER BY created_at DESC;`,
        [businessId, INITIAL_BUSINESS_ID]
      );
    } catch (colErr: any) {
      if (colErr.code === '42703') {
        // Safe fail-closed compatibility:
        // If the database has not yet been migrated to include business_id,
        // only the initial spa's data exists in this unpartitioned table.
        // A non-initial business has ZERO records and must NEVER receive the original spa's data!
        if (businessId !== INITIAL_BUSINESS_ID) {
          result = { rows: [] } as any;
        } else {
          result = await pool.query<{
            id: string;
            normalized_phone: string;
            display_name: string;
            created_at: Date;
            updated_at: Date;
          }>(
            `SELECT id, normalized_phone, display_name, created_at, updated_at
             FROM customers
             ORDER BY created_at DESC;`
          );
        }
      } else {
        throw colErr;
      }
    }

    res.json({
      success: true,
      count: result.rows.length,
      customers: result.rows.map((r) => ({
        id: r.id,
        phone: r.normalized_phone,
        name: r.display_name,
        createdAt: r.created_at.toISOString(),
        updatedAt: r.updated_at.toISOString(),
      })),
    });
  } catch (err: any) {
    console.error(`[Customers] Error fetching customers: ${err.message}`);
    res.status(500).json({
      success: false,
      error: { code: 'DATABASE_ERROR', message: 'Failed to retrieve customers' },
    });
  }
});

/**
 * POST /api/customers/bulk
 * Bulk imports customers assigned to the verified active business.
 */
router.post('/bulk', requireAuth, requireBusinessMembership(), async (req: Request, res: Response) => {
  const parsed = bulkImportCustomerSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: parsed.error.issues[0]?.message || 'Invalid customer import payload',
      },
    });
    return;
  }

  const pool = getPool();
  const businessId = req.business!.id;
  const client = await pool.connect();

  try {
    await client.query('BEGIN;');

    const importedIds: string[] = [];
    for (const cust of parsed.data.customers) {
      const normalizedPhone = normalizeWhatsAppPhone(cust.phone);
      if (!normalizedPhone) continue;

      const custId = cust.id || `cust_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;

      try {
        await client.query(
          `INSERT INTO customers (id, normalized_phone, display_name, business_id, created_at, updated_at)
           VALUES ($1, $2, $3, $4, NOW(), NOW())
           ON CONFLICT (id) DO UPDATE
           SET display_name = EXCLUDED.display_name,
               business_id = COALESCE(customers.business_id, EXCLUDED.business_id),
               updated_at = NOW();`,
          [custId, normalizedPhone, cust.name.trim(), businessId]
        );
      } catch (colErr: any) {
        if (colErr.code === '42703') {
          if (businessId !== INITIAL_BUSINESS_ID) {
            throw new Error('Multi-business schema migration required for non-initial business customer creation.');
          }
          await client.query(
            `INSERT INTO customers (id, normalized_phone, display_name, created_at, updated_at)
             VALUES ($1, $2, $3, NOW(), NOW())
             ON CONFLICT (id) DO UPDATE
             SET display_name = EXCLUDED.display_name, updated_at = NOW();`,
            [custId, normalizedPhone, cust.name.trim()]
          );
        } else {
          throw colErr;
        }
      }
      importedIds.push(custId);
    }

    await client.query('COMMIT;');

    res.status(201).json({
      success: true,
      totalRequested: parsed.data.customers.length,
      importedCount: importedIds.length,
      customerIds: importedIds,
    });
  } catch (err: any) {
    await client.query('ROLLBACK;');
    console.error(`[Customers] Error importing customers: ${err.message}`);
    res.status(500).json({
      success: false,
      error: { code: 'DATABASE_ERROR', message: 'Failed to import customers' },
    });
  } finally {
    client.release();
  }
});

/**
 * DELETE /api/customers
 * POST /api/customers/bulk-delete
 * Bulk deletes customer records strictly isolated to the authenticated business.
 */
async function handleBulkDelete(req: Request, res: Response) {
  const parsed = bulkDeleteSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: parsed.error.issues[0]?.message || 'Invalid customer deletion payload',
      },
    });
    return;
  }

  const { customerIds } = parsed.data;
  const pool = getPool();
  const businessId = req.business!.id;

  try {
    let result: { rows: Array<{ id: string }> };
    try {
      // Scoped deletion: only delete customers belonging to the active business
      result = await pool.query<{ id: string }>(
        `DELETE FROM customers
         WHERE id = ANY($1)
           AND (business_id = $2 OR (business_id IS NULL AND $2 = $3))
         RETURNING id;`,
        [customerIds, businessId, INITIAL_BUSINESS_ID]
      );
    } catch (colErr: any) {
      if (colErr.code === '42703') {
        if (businessId !== INITIAL_BUSINESS_ID) {
          result = { rows: [] } as any;
        } else {
          result = await pool.query<{ id: string }>(
            `DELETE FROM customers
             WHERE id = ANY($1)
             RETURNING id;`,
            [customerIds]
          );
        }
      } else {
        throw colErr;
      }
    }

    const deletedIds = result.rows.map((r) => r.id);

    console.log(
      `[Customers] Business ${businessId} deleted ${deletedIds.length} customer records (requested ${customerIds.length})`
    );

    res.status(200).json({
      success: true,
      totalRequested: customerIds.length,
      deletedCount: deletedIds.length,
      deletedCustomerIds: deletedIds,
    });
  } catch (err: any) {
    console.error(`[Customers] Error deleting customers: ${err.message}`);
    res.status(500).json({
      success: false,
      error: {
        code: 'DATABASE_ERROR',
        message: 'Failed to safely remove customer records',
      },
    });
  }
}

router.delete('/', requireAuth, requireBusinessMembership(), handleBulkDelete);
router.post('/bulk-delete', requireAuth, requireBusinessMembership(), handleBulkDelete);
router.post('/', requireAuth, requireBusinessMembership(), handleBulkDelete);

export default router;
