import { Router, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { z } from 'zod';
import { env } from '../config/env';
import { getPool } from '../db/pool';

const router = Router();

const bulkDeleteSchema = z.object({
  customerIds: z
    .array(z.string().min(1))
    .min(1, 'At least one customer ID is required')
    .max(500, 'Maximum 500 customers per batch'),
});

async function authenticate(req: Request, res: Response): Promise<{ userId: string } | null> {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({
      success: false,
      error: {
        code: 'UNAUTHORIZED',
        message: 'Authentication required for customer directory operations',
      },
    });
    return null;
  }

  const token = authHeader.substring(7).trim();
  try {
    const decoded = jwt.verify(token, env.JWT_SECRET) as { sub?: string; id?: string };
    const userId = decoded.sub || decoded.id || 'authenticated_user';
    return { userId };
  } catch {
    res.status(401).json({
      success: false,
      error: {
        code: 'UNAUTHORIZED',
        message: 'Invalid or expired authentication session',
      },
    });
    return null;
  }
}

/**
 * DELETE /api/customers
 * POST /api/customers/bulk-delete
 * Bulk deletes customer records from customers table while strictly preserving:
 * - customer_consent records (ON DELETE SET NULL ensures customer_id is nulled while keeping phone, status, and evidence)
 * - consent_audit_log (append-only compliance audit trail keyed by phone)
 * - campaign_messages & campaigns (historical dispatch records)
 */
async function handleBulkDelete(req: Request, res: Response) {
  const auth = await authenticate(req, res);
  if (!auth) return;

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

  try {
    const result = await pool.query<{ id: string }>(
      `DELETE FROM customers
       WHERE id = ANY($1)
       RETURNING id;`,
      [customerIds]
    );

    const deletedIds = result.rows.map((r) => r.id);

    console.log(
      `[Customers] Successfully deleted ${deletedIds.length} customer records (requested ${customerIds.length})`
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

router.delete('/', handleBulkDelete);
router.post('/bulk-delete', handleBulkDelete);
router.post('/', handleBulkDelete);

export default router;
