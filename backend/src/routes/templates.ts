import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { TemplateService } from '../services/templateService';
import {
  requireAuth,
  requireBusinessMembership,
  requireAuthorizedWhatsAppConnection,
} from '../middleware/authMiddleware';

const router = Router();

// Mount authentication and business context middleware
router.use(requireAuth);
router.use(requireBusinessMembership());

const createTemplateSchema = z.object({
  name: z
    .string()
    .min(1, 'Template name is required')
    .regex(/^[a-z0-9_]+$/, 'Template name must contain only lowercase alphanumeric characters and underscores'),
  displayName: z.string().min(1, 'Display name is required'),
  description: z.string().optional(),
  category: z.enum(['MARKETING', 'UTILITY', 'AUTHENTICATION']).default('MARKETING'),
  language: z.string().default('en_US'),
  body: z.string().min(1, 'Message body is required'),
  variables: z.array(z.string()).optional(),
  exampleValues: z.record(z.string()).optional(),
  submitToMeta: z.boolean().default(false),
});

const updateStatusSchema = z.object({
  status: z.enum(['draft', 'pending_approval', 'approved', 'rejected', 'disabled']),
  metaStatus: z
    .enum(['APPROVED', 'PENDING', 'REJECTED', 'PAUSED', 'DISABLED', 'NOT_SUBMITTED'])
    .optional(),
});

/**
 * GET /api/templates
 * Lists all WhatsApp templates scoped to the authenticated business (optionally filtered by ?mode=test|production).
 */
router.get('/', async (req: Request, res: Response) => {
  const mode = req.query.mode === 'production' ? 'production' : req.query.mode === 'test' ? 'test' : undefined;
  const templates = await TemplateService.listTemplates(mode, req.business!.id);
  res.json({
    success: true,
    count: templates.length,
    mode: mode || 'all',
    templates,
  });
});

/**
 * GET /api/templates/:id
 * Retrieves a single template by ID or Meta name, scoped to authenticated business.
 */
router.get('/:id', async (req: Request, res: Response) => {
  const mode = req.query.mode === 'production' ? 'production' : req.query.mode === 'test' ? 'test' : undefined;
  const template = await TemplateService.getTemplate(req.params.id, mode, req.business!.id);
  if (!template) {
    res.status(404).json({
      success: false,
      error: {
        code: 'TEMPLATE_NOT_FOUND',
        message: `Template '${req.params.id}' was not found.`,
      },
    });
    return;
  }
  res.json({
    success: true,
    template,
  });
});

/**
 * POST /api/templates
 * Creates a new template assigned to the authenticated business. Requires admin/owner role.
 */
router.post('/', requireBusinessMembership('admin'), async (req: Request, res: Response) => {
  const parsed = createTemplateSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Invalid template creation payload',
        details: parsed.error.format(),
      },
    });
    return;
  }

  const result = await TemplateService.createTemplate(parsed.data, req.business!.id);
  res.status(201).json({
    success: true,
    template: result.template,
    metaError: result.metaError,
  });
});

/**
 * POST /api/templates/sync
 * Synchronizes templates with official Meta WhatsApp Cloud API / WABA account.
 * Restricts sync to the initial business with verified WhatsApp connection.
 */
router.post('/sync', requireAuthorizedWhatsAppConnection, async (req: Request, res: Response) => {
  const rawMode = req.query.mode || req.body?.mode;
  const mode = rawMode === 'production' ? 'production' : 'test';
  const result = await TemplateService.syncFromMeta(mode, req.business!.id);
  res.json({
    success: result.success,
    mode,
    syncedCount: result.syncedCount,
    templates: result.templates,
    error: result.error,
  });
});

/**
 * PUT /api/templates/:id/status
 * Updates template approval status.
 */
router.put('/:id/status', async (req: Request, res: Response) => {
  const parsed = updateStatusSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Invalid status update payload',
        details: parsed.error.format(),
      },
    });
    return;
  }

  const existing = await TemplateService.getTemplate(req.params.id, undefined, req.business!.id);
  if (!existing) {
    res.status(404).json({
      success: false,
      error: {
        code: 'TEMPLATE_NOT_FOUND',
        message: `Template '${req.params.id}' was not found.`,
      },
    });
    return;
  }

  const updated = await TemplateService.updateStatus(
    req.params.id,
    parsed.data.status,
    parsed.data.metaStatus
  );

  res.json({
    success: true,
    template: updated,
  });
});

/**
 * DELETE /api/templates/:id
 * Removes a template scoped to the active business.
 */
router.delete('/:id', async (req: Request, res: Response) => {
  const deleted = await TemplateService.deleteTemplate(req.params.id, req.business!.id);
  if (!deleted) {
    res.status(404).json({
      success: false,
      error: {
        code: 'TEMPLATE_NOT_FOUND',
        message: `Template '${req.params.id}' was not found.`,
      },
    });
    return;
  }

  res.json({
    success: true,
    message: `Template '${req.params.id}' deleted successfully.`,
  });
});

export default router;
