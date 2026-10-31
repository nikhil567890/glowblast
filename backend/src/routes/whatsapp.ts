import { Router, Request, Response } from 'express';
import { env, getSafeConfigStatus, getAuthorizedTestRecipients } from '../config/env';
import { singleMessageSchema } from '../utils/validation';
import { normalizeWhatsAppPhone } from '../utils/phone';
import { WhatsAppService } from '../services/whatsappService';
import { templateStore } from '../store/templateStore';
import { wabaConnectionStore } from '../store/wabaConnectionStore';
import { resolveBusinessWhatsAppCredentials } from '../services/credentialResolver';
import {
  requireAuth,
  requireBusinessMembership,
  requireAuthorizedWhatsAppConnection,
  INITIAL_BUSINESS_ID,
} from '../middleware/authMiddleware';

const router = Router();

/**
 * GET /api/whatsapp/status
 * Returns safe Meta configuration status. Never returns secret tokens.
 */
router.get('/status', async (req: Request, res: Response) => {
  const baseStatus = getSafeConfigStatus();
  res.json(baseStatus);
});

/**
 * GET /api/whatsapp/connection
 * Retrieves safe WhatsApp Business connection status for authenticated business.
 */
router.get(
  '/connection',
  requireAuth,
  requireBusinessMembership(),
  async (req: Request, res: Response) => {
    const businessId = req.business!.id;
    const mode = (req.query.mode as any) === 'production' ? 'production' : 'test';

    const safeConn = await wabaConnectionStore.getSafeConnection(businessId, mode);
    if (safeConn) {
      res.json({
        success: true,
        connected: true,
        source: 'database',
        connection: safeConn,
      });
      return;
    }

    // Controlled fallback representation for initial spa
    if (businessId === INITIAL_BUSINESS_ID) {
      try {
        const legacyCreds = await resolveBusinessWhatsAppCredentials(businessId, mode);
        res.json({
          success: true,
          connected: true,
          source: 'initial_spa_legacy_fallback',
          connection: {
            id: 'conn_initial_legacy_v1',
            businessId: INITIAL_BUSINESS_ID,
            wabaId: legacyCreds.wabaId,
            phoneNumberId: legacyCreds.phoneNumberId,
            displayNumber: legacyCreds.displayNumber,
            mode,
            isActive: true,
            verifiedName: req.business!.displayName,
            qualityRating: 'UNKNOWN',
            createdAt: req.business!.createdAt.toISOString(),
            updatedAt: req.business!.updatedAt.toISOString(),
          },
        });
        return;
      } catch (_) {}
    }

    res.json({
      success: true,
      connected: false,
      source: 'none',
      connection: null,
    });
  }
);

/**
 * POST /api/whatsapp/connection
 * Connects or updates a WhatsApp Business Account connection for the active business.
 * Encrypts access token using AES-256-GCM. Never returns token in response.
 * Requires Admin or Owner role.
 */
router.post(
  '/connection',
  requireAuth,
  requireBusinessMembership('admin'),
  async (req: Request, res: Response) => {
    const { wabaId, phoneNumberId, accessToken, displayNumber, mode, metaAppId, verifiedName } = req.body;

    if (!wabaId || typeof wabaId !== 'string' || wabaId.trim().length === 0) {
      res.status(400).json({
        success: false,
        error: {
          code: 'MISSING_WABA_ID',
          message: 'Meta WhatsApp Business Account ID (WABA ID) is required.',
        },
      });
      return;
    }

    if (!phoneNumberId || typeof phoneNumberId !== 'string' || phoneNumberId.trim().length === 0) {
      res.status(400).json({
        success: false,
        error: {
          code: 'MISSING_PHONE_NUMBER_ID',
          message: 'Meta Phone Number ID is required.',
        },
      });
      return;
    }

    if (!accessToken || typeof accessToken !== 'string' || accessToken.trim().length === 0) {
      res.status(400).json({
        success: false,
        error: {
          code: 'MISSING_ACCESS_TOKEN',
          message: 'Meta System User Access Token is required.',
        },
      });
      return;
    }

    const connMode = mode === 'production' ? 'production' : 'test';

    let metaVerified = false;
    let codeVerificationStatus = connMode === 'test' ? 'TEST_PROVISIONED' : 'SAVED_UNVERIFIED';
    let resolvedVerifiedName = verifiedName ? String(verifiedName).trim() : req.business!.displayName;
    let resolvedDisplayNumber = displayNumber ? String(displayNumber).trim() : undefined;
    let resolvedQualityRating = 'UNKNOWN';

    // Verify phone number ID and access token against Meta Graph API where reachable
    try {
      const metaCheckUrl = `https://graph.facebook.com/${env.WHATSAPP_API_VERSION}/${phoneNumberId.trim()}?fields=id,display_phone_number,verified_name,quality_rating,code_verification_status`;
      const metaRes = await fetch(metaCheckUrl, {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${accessToken.trim()}`,
        },
        signal: AbortSignal.timeout(5000),
      });

      if (metaRes.ok) {
        const metaData = (await metaRes.json()) as any;
        metaVerified = true;
        codeVerificationStatus = metaData.code_verification_status || 'VERIFIED';
        if (metaData.verified_name) resolvedVerifiedName = metaData.verified_name;
        if (metaData.display_phone_number) resolvedDisplayNumber = metaData.display_phone_number;
        if (metaData.quality_rating) resolvedQualityRating = metaData.quality_rating;
      } else {
        const metaErr = (await metaRes.json().catch(() => ({}))) as any;
        if (connMode === 'production' && metaRes.status === 401) {
          res.status(400).json({
            success: false,
            error: {
              code: 'INVALID_META_CREDENTIALS',
              message: metaErr?.error?.message || 'Meta rejected access token or phone number ID.',
            },
          });
          return;
        }
        codeVerificationStatus = 'META_CHECK_FAILED';
      }
    } catch (_) {
      // Offline, network timeout, or test environment: preserve unverified status without false claim
      codeVerificationStatus = connMode === 'test' ? 'TEST_PROVISIONED' : 'SAVED_UNVERIFIED';
    }

    try {
      const saved = await wabaConnectionStore.saveConnection({
        businessId: req.business!.id,
        wabaId: wabaId.trim(),
        phoneNumberId: phoneNumberId.trim(),
        plainAccessToken: accessToken.trim(),
        displayNumber: resolvedDisplayNumber,
        mode: connMode,
        metaAppId: metaAppId ? String(metaAppId).trim() : undefined,
        verifiedName: resolvedVerifiedName,
        qualityRating: resolvedQualityRating,
        codeVerificationStatus,
      });

      res.status(201).json({
        success: true,
        message: metaVerified
          ? 'WhatsApp Business Account successfully verified with Meta and encrypted.'
          : 'WhatsApp Business Account credentials saved and encrypted (live Meta verification pending).',
        verifiedWithMeta: metaVerified,
        connection: {
          id: saved.id,
          businessId: saved.businessId,
          wabaId: saved.wabaId,
          phoneNumberId: saved.phoneNumberId,
          displayNumber: saved.displayNumber,
          mode: saved.mode,
          isActive: saved.isActive,
          verifiedName: saved.verifiedName,
          qualityRating: saved.qualityRating,
          codeVerificationStatus: saved.codeVerificationStatus,
          createdAt: saved.createdAt.toISOString(),
          updatedAt: saved.updatedAt.toISOString(),
        },
      });
    } catch (saveErr: any) {
      console.error('[WhatsApp Connection Error] Failed to connect WABA:', saveErr.message);
      res.status(saveErr.message.includes('ENCRYPTION') ? 500 : 400).json({
        success: false,
        error: {
          code: saveErr.code || 'CONNECTION_FAILED',
          message: saveErr.message || 'Failed to securely persist WhatsApp connection.',
        },
      });
    }
  }
);

/**
 * DELETE /api/whatsapp/connection
 * Disconnects active WhatsApp connection for current business.
 */
router.delete(
  '/connection',
  requireAuth,
  requireBusinessMembership('admin'),
  async (req: Request, res: Response) => {
    const mode = (req.query.mode as any) === 'production' ? 'production' : 'test';
    const deactivated = await wabaConnectionStore.deactivateConnection(req.business!.id, mode);
    res.json({
      success: true,
      deactivated,
      message: 'WhatsApp Business Account disconnected.',
    });
  }
);

/**
 * POST /api/whatsapp/send
 * Sends a single test message using official Meta Cloud API.
 * Protected by authentication, business membership, and authorized WhatsApp connection.
 */
router.post(
  '/send',
  requireAuth,
  requireBusinessMembership(),
  requireAuthorizedWhatsAppConnection,
  async (req: Request, res: Response) => {
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

    // Check template mapping and approval scoped to business
    const template = await templateStore.findByIdOrName(templateId || templateName, undefined, undefined, req.business!.id);
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
            textVal = req.business?.displayName || 'Our Spa & Wellness';
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

    // Resolve credentials through verified business context
    let credentials;
    try {
      credentials = await resolveBusinessWhatsAppCredentials(req.business!.id, 'test');
    } catch (credErr: any) {
      res.status(credErr.httpStatus || 403).json({
        success: false,
        error: {
          code: credErr.code || 'WHATSAPP_CONNECTION_NOT_CONFIGURED',
          message: credErr.message,
        },
      });
      return;
    }

    const result = await WhatsAppService.sendTemplateMessage({
      recipientPhone: normalizedPhone,
      recipientName: name ?? undefined,
      templateName: effectiveMetaTemplateName,
      templateLanguage: effectiveLanguage,
      templateComponents: effectiveMetaTemplateName === 'hello_world' ? undefined : ((effectiveComponents ?? undefined) as any),
      credentials: {
        phoneNumberId: credentials.phoneNumberId,
        accessToken: credentials.accessToken,
      },
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
  }
);

export default router;
