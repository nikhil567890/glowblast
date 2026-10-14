import { Router, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { z } from 'zod';
import { env, isEmailAuthorizedForProduction } from '../config/env';
import { consentStore, ConsentStatus } from '../store/consentStore';
import { userStore } from '../store/userStore';

const router = Router();

const recordConsentSchema = z.object({
  phone: z.string().min(10, 'Valid phone number is required'),
  status: z.enum(['opted_in', 'opted_out', 'revoked']),
  source: z.string().min(3, 'Consent source is required (e.g. written_signed_waiver, front_desk_digital_form)'),
  evidence: z.string().min(5, 'Auditable evidence reference is required (e.g. waiver number, form ID, or signed document reference)'),
  allowOptOutOverride: z.boolean().optional(),
});

/**
 * Authentication and authorization middleware helper for consent registry operations.
 * Only verified server-side identities may view or record consent.
 */
async function authenticateAndAuthorize(req: Request, res: Response): Promise<{ userId: string; userEmail?: string } | null> {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({
      success: false,
      error: {
        code: 'UNAUTHORIZED',
        message: 'Authentication required to manage consent registry',
      },
    });
    return null;
  }

  const token = authHeader.substring(7).trim();
  try {
    const decoded = jwt.verify(token, env.JWT_SECRET) as { sub?: string; email?: string; id?: string };
    const userId = decoded.sub || decoded.id || 'authenticated_user';
    let userEmail: string | undefined = undefined;

    const serverUser = decoded.sub ? await userStore.findById(decoded.sub) : undefined;
    if (serverUser && serverUser.email) {
      userEmail = serverUser.email.trim().toLowerCase();
    } else if (decoded.email && typeof decoded.email === 'string') {
      userEmail = decoded.email.trim().toLowerCase();
    } else if (decoded.sub && decoded.sub.includes('@')) {
      userEmail = decoded.sub.trim().toLowerCase();
    }

    return { userId, userEmail };
  } catch {
    res.status(401).json({
      success: false,
      error: {
        code: 'UNAUTHORIZED',
        message: 'Invalid or expired authentication token',
      },
    });
    return null;
  }
}

/**
 * POST /api/consent/record
 * Authoritative recording of customer WhatsApp consent or opt-out.
 */
router.post('/record', async (req: Request, res: Response) => {
  const auth = await authenticateAndAuthorize(req, res);
  if (!auth) return;

  // Only authorized administrators can record or update customer WhatsApp consent
  const isAuthorizedAdmin = !!(auth.userEmail && isEmailAuthorizedForProduction(auth.userEmail));
  if (!isAuthorizedAdmin) {
    res.status(403).json({
      success: false,
      error: {
        code: 'FORBIDDEN',
        message: 'Only authorized administrators (PRODUCTION_ALLOWED_EMAILS) may record or modify customer WhatsApp consent.',
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

  const { phone, status, source, evidence, allowOptOutOverride } = parsed.data;
  const updatedBy = auth.userEmail || auth.userId;

  const record = await consentStore.recordConsent({
    phone,
    status: status as ConsentStatus,
    source,
    evidence,
    updatedBy,
    isAuthorizedAdmin,
    allowOptOutOverride: allowOptOutOverride === true,
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
 * GET /api/consent/:phone
 * Query server-side consent status for a recipient.
 */
router.get('/:phone', async (req: Request, res: Response) => {
  const auth = await authenticateAndAuthorize(req, res);
  if (!auth) return;

  const { phone } = req.params;
  const record = await consentStore.getConsent(phone);

  if (!record) {
    res.status(404).json({
      success: false,
      hasConsent: false,
      status: 'unknown',
      message: 'No consent record exists for this recipient in server registry.',
    });
    return;
  }

  res.status(200).json({
    success: true,
    hasConsent: record.status === 'opted_in',
    record,
  });
});

export default router;
