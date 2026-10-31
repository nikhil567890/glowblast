import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { isEmailAuthorizedForProduction } from '../config/env';
import { consentStore, ConsentStatus, ConsentCategory } from '../store/consentStore';
import { requireAuth, requireBusinessMembership } from '../middleware/authMiddleware';

const router = Router();

// Mount authentication and business context middleware
router.use(requireAuth);
router.use(requireBusinessMembership());

const recordConsentSchema = z.object({
  phone: z.string().min(10, 'Valid phone number is required'),
  customerId: z.string().optional(),
  consentCategory: z.enum(['marketing', 'utility', 'unclassified']).default('marketing'),
  status: z.enum(['opted_in', 'opted_out', 'revoked']),
  source: z.string().min(3, 'Consent source is required (e.g. written_signed_waiver, front_desk_digital_form)'),
  evidence: z.string().min(3, 'Auditable evidence reference is required (e.g. waiver number, form ID, or signed document reference)'),
  consentTextVersion: z.string().optional(),
  allowOptOutOverride: z.boolean().optional(),
});

const batchCheckSchema = z.object({
  phones: z.array(z.string()),
  category: z.enum(['marketing', 'utility', 'unclassified']).default('marketing'),
});

const bulkRecordSchema = z.object({
  records: z.array(
    z.object({
      phone: z.string().min(10, 'Valid phone number is required'),
      customerId: z.string().optional(),
      source: z.string().min(3, 'Consent source is required'),
      evidence: z.string().min(3, 'Auditable evidence reference is required'),
      consentTextVersion: z.string().optional(),
    })
  ).min(1).max(500, 'Bulk consent limited to 500 records per request'),
  allowOptOutOverride: z.boolean().default(false),
});

/**
 * POST /api/consent/record
 * Authoritative recording of customer WhatsApp consent or opt-out scoped to active business.
 */
router.post('/record', async (req: Request, res: Response) => {
  const userEmail = req.user?.email?.toLowerCase().trim();
  const isAuthorizedAdmin = req.membership?.role === 'owner' || req.membership?.role === 'admin' || !!(userEmail && isEmailAuthorizedForProduction(userEmail));
  
  if (!isAuthorizedAdmin) {
    res.status(403).json({
      success: false,
      error: {
        code: 'FORBIDDEN',
        message: 'Only business owners, administrators, or authorized production emails may record or modify customer WhatsApp consent.',
      },
    });
    return;
  }

  const parsed = recordConsentSchema.safeParse(req.body);
  if (!parsed.success) {
    const firstIssue = parsed.error.issues[0]?.message || 'Invalid consent payload';
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: firstIssue,
      },
    });
    return;
  }

  const { phone, customerId, consentCategory, status, source, evidence, consentTextVersion, allowOptOutOverride } = parsed.data;
  const updatedBy = userEmail || req.user?.id || 'authenticated_user';

  if (status === 'opted_in' && consentCategory === 'unclassified') {
    res.status(400).json({
      success: false,
      error: {
        code: 'INVALID_CONSENT_CATEGORY',
        message: 'Explicit marketing or utility category is required for opt-in. Unclassified is reserved for historical unverified records.',
      },
    });
    return;
  }

  const record = await consentStore.recordConsent({
    phone,
    customerId,
    consentCategory: consentCategory as ConsentCategory,
    status: status as ConsentStatus,
    source,
    evidence,
    consentTextVersion,
    updatedBy,
    isAuthorizedAdmin,
    allowOptOutOverride: allowOptOutOverride === true,
    businessId: req.business!.id,
  });

  if (!record) {
    res.status(400).json({
      success: false,
      error: {
        code: 'CONSENT_RECORD_FAILED',
        message: 'Consent update rejected. Reversing an opt-out requires allowOptOutOverride: true and verified administrator authorization.',
      },
    });
    return;
  }

  res.status(200).json({
    success: true,
    record,
  });
});

/**
 * POST /api/consent/bulk-record
 * Records verbal marketing opt-in for a batch of customers scoped to active business.
 */
router.post('/bulk-record', async (req: Request, res: Response) => {
  const userEmail = req.user?.email?.toLowerCase().trim();
  const isAuthorizedAdmin = req.membership?.role === 'owner' || req.membership?.role === 'admin' || !!(userEmail && isEmailAuthorizedForProduction(userEmail));
  
  if (!isAuthorizedAdmin) {
    res.status(403).json({
      success: false,
      error: {
        code: 'FORBIDDEN',
        message: 'Only business owners, administrators, or authorized production emails may record bulk consent.',
      },
    });
    return;
  }

  const parsed = bulkRecordSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: parsed.error.issues[0]?.message || 'Invalid bulk consent payload',
      },
    });
    return;
  }

  const { records, allowOptOutOverride } = parsed.data;
  const updatedBy = userEmail || req.user?.id || 'authenticated_user';

  const outcome = await consentStore.bulkRecordConsent({
    records: records.map((entry) => ({
      phone: entry.phone,
      customerId: entry.customerId,
      consentCategory: 'marketing',
      status: 'opted_in',
      source: entry.source,
      evidence: entry.evidence,
      consentTextVersion: entry.consentTextVersion || 'v2026.1_verbal_confirmed',
    })),
    updatedBy,
    isAuthorizedAdmin,
    allowOptOutOverride,
    businessId: req.business!.id,
  });

  res.status(200).json({
    success: outcome.failed === 0,
    totalRequested: outcome.totalRequested,
    succeeded: outcome.succeeded,
    failed: outcome.failed,
    results: outcome.results,
    failures: outcome.failures,
  });
});

/**
 * GET /api/consent
 * Returns all consent records for the authenticated business, optionally filtered by category.
 */
router.get('/', async (req: Request, res: Response) => {
  const categoryQuery = req.query.category as string | undefined;
  const validCategory = (categoryQuery === 'marketing' || categoryQuery === 'utility' || categoryQuery === 'unclassified') ? (categoryQuery as ConsentCategory) : undefined;
  const records = await consentStore.getAll(validCategory, req.business!.id);

  res.status(200).json({
    success: true,
    count: records.length,
    records,
  });
});

/**
 * POST /api/consent/batch-check
 * Efficiently checks consent for an array of recipient phone numbers within the business.
 */
router.post('/batch-check', async (req: Request, res: Response) => {
  const parsed = batchCheckSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: parsed.error.issues[0]?.message || 'Invalid batch payload',
      },
    });
    return;
  }

  const { phones, category } = parsed.data;
  const results: Record<string, { hasConsent: boolean; status: string; category: string }> = {};

  for (const phone of phones) {
    const hasConsent = await consentStore.hasActiveConsent(phone, category as ConsentCategory, req.business!.id);
    const record = await consentStore.getConsent(phone, category as ConsentCategory, req.business!.id);
    results[phone] = {
      hasConsent,
      status: record?.status || 'unknown',
      category,
    };
  }

  res.status(200).json({
    success: true,
    results,
  });
});

/**
 * GET /api/consent/:phone
 * Query server-side consent status for a recipient within the business.
 */
router.get('/:phone', async (req: Request, res: Response) => {
  const { phone } = req.params;
  const categoryQuery = req.query.category as string | undefined;

  if (categoryQuery === 'marketing' || categoryQuery === 'utility') {
    const record = await consentStore.getConsent(phone, categoryQuery as ConsentCategory, req.business!.id);
    res.status(200).json({
      success: true,
      hasConsent: record?.status === 'opted_in',
      status: record?.status || 'unknown',
      record: record || null,
      category: categoryQuery,
    });
    return;
  }

  // If no category specified, return both marketing and utility records
  const allRecords = await consentStore.getConsentsForPhone(phone, req.business!.id);
  const marketingRecord = allRecords.find((r) => r.consentCategory === 'marketing');
  const utilityRecord = allRecords.find((r) => r.consentCategory === 'utility');

  res.status(200).json({
    success: true,
    phone,
    hasMarketingConsent: marketingRecord?.status === 'opted_in',
    hasUtilityConsent: utilityRecord?.status === 'opted_in',
    marketing: marketingRecord || null,
    utility: utilityRecord || null,
    records: allRecords,
  });
});

export default router;
