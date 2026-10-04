import { Router, Request, Response } from 'express';
import { getSafeConfigStatus, getAuthorizedTestRecipients } from '../config/env';
import { singleMessageSchema } from '../utils/validation';
import { normalizeWhatsAppPhone } from '../utils/phone';
import { WhatsAppService } from '../services/whatsappService';

const router = Router();

/**
 * GET /api/whatsapp/status
 * Returns safe Meta configuration status. Never returns secret tokens.
 */
router.get('/status', (_req: Request, res: Response) => {
  res.json(getSafeConfigStatus());
});

/**
 * POST /api/whatsapp/send
 * Sends a single test message using official Meta Cloud API.
 */
router.post('/send', async (req: Request, res: Response) => {
  const parsed = singleMessageSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Invalid request body',
        details: parsed.error.format(),
      },
    });
    return;
  }

  const { phone, name, templateName, templateLanguage } = parsed.data;

  const normalizedPhone = normalizeWhatsAppPhone(phone);
  if (!normalizedPhone) {
    res.status(400).json({
      success: false,
      error: {
        code: 'INVALID_PHONE',
        message: 'Phone number could not be normalized for WhatsApp.',
      },
    });
    return;
  }

  // Check authorized test allowlist if defined
  const allowlist = getAuthorizedTestRecipients();
  if (allowlist.length > 0 && !allowlist.includes(normalizedPhone)) {
    res.status(403).json({
      success: false,
      error: {
        code: 'UNAUTHORIZED_TEST_RECIPIENT',
        message: 'Phone number is not in authorized Meta test recipient allowlist.',
      },
    });
    return;
  }

  const result = await WhatsAppService.sendTemplateMessage({
    recipientPhone: normalizedPhone,
    recipientName: name,
    templateName,
    templateLanguage,
  });

  if (!result.success) {
    res.status(result.errorCode === 401 ? 401 : 400).json({
      success: false,
      error: {
        code: result.errorCode?.toString() || 'SEND_FAILED',
        title: result.errorTitle,
        message: result.errorMessage,
      },
    });
    return;
  }

  res.json({
    success: true,
    providerMessageId: result.providerMessageId,
    status: 'accepted',
  });
});

export default router;
