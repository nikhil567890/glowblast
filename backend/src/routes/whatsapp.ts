import { Router, Request, Response } from 'express';
import { getSafeConfigStatus, getAuthorizedTestRecipients } from '../config/env';
import { singleMessageSchema } from '../utils/validation';
import { normalizeWhatsAppPhone } from '../utils/phone';
import { WhatsAppService } from '../services/whatsappService';
import { templateStore } from '../store/templateStore';

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

  const { phone, name, templateId, templateName, templateLanguage, templateComponents, templateVariables } = parsed.data;

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

  // Check template mapping and approval
  const template = templateStore.findByIdOrName(templateId || templateName);
  let effectiveMetaTemplateName = templateName;
  let effectiveLanguage = templateLanguage || 'en_US';
  let effectiveComponents = templateComponents;

  if (template) {
    if (template.status !== 'approved') {
      res.status(400).json({
        success: false,
        error: {
          code: 'TEMPLATE_NOT_APPROVED',
          message: `This GlowBlast template is not connected to an approved WhatsApp template yet (status: ${template.status}).`,
        },
      });
      return;
    }
    effectiveMetaTemplateName = template.name;
    effectiveLanguage = template.language || effectiveLanguage;

    if (!effectiveComponents && template.variables && template.variables.length > 0) {
      const vars = templateVariables && templateVariables.length > 0 ? templateVariables : template.variables;
      const paramsList = vars.map((v) => {
        const vLower = v.toLowerCase();
        let textVal = '';
        if (vLower === 'name' || vLower === 'customer_name' || vLower === 'client') {
          textVal = name || 'Client';
        } else if (vLower === 'business_name' || vLower === 'spa_name') {
          textVal = 'Our Spa & Wellness';
        } else if (template.exampleValues?.[v]) {
          textVal = template.exampleValues[v];
        } else {
          textVal = v;
        }
        return { type: 'text', text: textVal };
      });
      effectiveComponents = [{ type: 'body', parameters: paramsList }];
    }
  } else if (templateName !== 'hello_world') {
    res.status(400).json({
      success: false,
      error: {
        code: 'UNMAPPED_TEMPLATE',
        message: 'This GlowBlast template is not connected to an approved WhatsApp template yet.',
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
    templateName: effectiveMetaTemplateName,
    templateLanguage: effectiveLanguage,
    templateComponents: effectiveMetaTemplateName === 'hello_world' ? undefined : effectiveComponents,
  });

  if (!result.success) {
    res.status(result.errorCode === 401 ? 401 : 400).json({
      success: false,
      error: {
        code: result.errorCode?.toString() || 'SEND_FAILED',
        title: result.errorTitle,
        message: result.errorMessage,
        details: result.errorDetails,
        requestedTemplateName: result.requestedTemplateName || effectiveMetaTemplateName,
        requestedTemplateLanguage: result.requestedTemplateLanguage || effectiveLanguage,
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
