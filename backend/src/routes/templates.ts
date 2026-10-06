import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { TemplateService } from '../services/templateService';

const router = Router();

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
 * Lists all WhatsApp templates.
 */
router.get('/', (_req: Request, res: Response) => {
  const templates = TemplateService.listTemplates();
  res.json({
    success: true,
    count: templates.length,
    templates,
  });
});

/**
 * GET /api/templates/:id
 * Retrieves a single template by ID or Meta name.
 */
router.get('/:id', (req: Request, res: Response) => {
  const template = TemplateService.getTemplate(req.params.id);
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
 * Creates a new template and optionally submits it to Meta WhatsApp Business API.
 */
router.post('/', async (req: Request, res: Response) => {
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

  const result = await TemplateService.createTemplate(parsed.data);
  res.status(201).json({
    success: true,
    template: result.template,
    metaError: result.metaError,
  });
});

/**
 * POST /api/templates/sync
 * Synchronizes templates with official Meta WhatsApp Cloud API / WABA account.
 */
router.post('/sync', async (_req: Request, res: Response) => {
  const result = await TemplateService.syncFromMeta();
  res.json({
    success: result.success,
    syncedCount: result.syncedCount,
    templates: result.templates,
    error: result.error,
  });
});

/**
 * PUT /api/templates/:id/status
 * Updates template approval status (e.g. manual import / confirmation).
 */
router.put('/:id/status', (req: Request, res: Response) => {
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

  const updated = TemplateService.updateStatus(
    req.params.id,
    parsed.data.status,
    parsed.data.metaStatus
  );

  if (!updated) {
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
    template: updated,
  });
});

/**
 * DELETE /api/templates/:id
 * Removes a template from local store.
 */
router.delete('/:id', (req: Request, res: Response) => {
  const deleted = TemplateService.deleteTemplate(req.params.id);
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
