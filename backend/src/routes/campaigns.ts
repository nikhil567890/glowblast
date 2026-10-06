import { Router, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../config/env';
import { campaignSendSchema } from '../utils/validation';
import { CampaignService } from '../services/campaignService';
import { campaignStore } from '../store/campaignStore';
import { realtimeService } from '../services/realtimeService';

const router = Router();

/**
 * POST /api/campaigns/send
 * Dispatches a WhatsApp campaign (max 5 recipients in test mode).
 * Requires JWT authentication via Authorization: Bearer <JWT>
 */
router.post('/send', async (req: Request, res: Response) => {
  // 1. Verify JWT Authentication
  const authHeader = req.headers.authorization;
  const authHeaderPresent = !!(authHeader && authHeader.startsWith('Bearer '));
  let authValid = false;
  let userId = 'unauthenticated';

  if (authHeaderPresent && authHeader) {
    const token = authHeader.substring(7).trim();
    try {
      const decoded = jwt.verify(token, env.JWT_SECRET) as { sub?: string; email?: string; id?: string };
      authValid = true;
      userId = decoded.sub || decoded.id || decoded.email || 'authenticated_user';
    } catch (_) {
      authValid = false;
    }
  }

  // Safe diagnostics (never logs secrets, JWT, tokens, or PII)
  console.log(`[Campaign] Send request received\nauthHeaderPresent=${authHeaderPresent}\nauthValid=${authValid}\nuserId=${userId}`);

  if (!authHeaderPresent || !authValid) {
    console.warn(`[Campaign] Rejected:\nreason=UNAUTHORIZED`);
    res.status(401).json({
      success: false,
      error: {
        code: 'UNAUTHORIZED',
        message: 'Authentication required',
      },
    });
    return;
  }

  // 2. Safe Payload Metadata Logging
  const payloadKeys = req.body && typeof req.body === 'object' ? Object.keys(req.body) : [];
  const recipientsCount = Array.isArray(req.body?.recipients) ? req.body.recipients.length : 0;
  const reqTemplateName = typeof req.body?.templateName === 'string' ? req.body.templateName : 'unknown';
  const reqTemplateLanguage = typeof req.body?.templateLanguage === 'string' ? req.body.templateLanguage : 'en_US';

  console.log(
    `[Campaign] Send request received\n` +
    `payloadKeys=${JSON.stringify(payloadKeys)}\n` +
    `recipientsCount=${recipientsCount}\n` +
    `templateName=${reqTemplateName}\n` +
    `templateLanguage=${reqTemplateLanguage}`
  );

  // 3. Schema Validation
  const parsed = campaignSendSchema.safeParse(req.body);
  if (!parsed.success) {
    const issues = parsed.error.issues;
    const errorFields = Array.from(new Set(issues.map((i) => i.path.join('.') || 'body')));
    const firstMessage = issues[0]?.message || 'Invalid campaign payload format';

    console.warn(`[Campaign] Rejected:\nreason=VALIDATION_ERROR\nfields=${JSON.stringify(errorFields)}`);
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: firstMessage !== 'Required' && !firstMessage.startsWith('Expected')
          ? firstMessage
          : `Invalid campaign data: ${errorFields.join(', ')}`,
        fields: errorFields,
      },
    });
    return;
  }

  // 4. Dispatch Campaign
  const result = await CampaignService.dispatchCampaign({
    ...parsed.data,
    campaignId: parsed.data.campaignId || `GB-${Date.now()}`,
    templateLanguage: parsed.data.templateLanguage || 'en_US',
    templateComponents: (parsed.data.templateComponents ?? undefined) as any,
    recipients: parsed.data.recipients.map((r, idx) => ({
      localCustomerId: r.localCustomerId || `cust_${idx + 1}`,
      name: r.name || 'Valued Customer',
      phone: r.phone,
    })),
  });

  if (!result.success) {
    const errCode = result.error?.code || 'DISPATCH_ERROR';
    console.warn(`[Campaign] Rejected:\nreason=${errCode}`);
    const statusCode = errCode === 'CAMPAIGN_NOT_FOUND' ? 404 : 400;
    res.status(statusCode).json({
      success: false,
      error: {
        code: errCode,
        message: result.error?.message || 'Failed to dispatch campaign',
      },
    });
    return;
  }

  res.status(202).json({
    success: true,
    campaignId: result.campaign?.campaignId,
    status: result.campaign?.status,
    total: result.campaign?.total,
    message: 'Campaign accepted for processing',
  });
});

/**
 * GET /api/campaigns/:campaignId
 * Returns the current authoritative campaign state.
 */
router.get('/:campaignId', (req: Request, res: Response) => {
  const { campaignId } = req.params;
  const summary = campaignStore.getSummary(campaignId);
  const camp = campaignStore.get(campaignId);

  if (!summary || !camp) {
    res.status(404).json({
      success: false,
      error: {
        code: 'CAMPAIGN_NOT_FOUND',
        message: `Campaign with ID '${campaignId}' was not found.`,
      },
    });
    return;
  }

  res.json({
    success: true,
    campaign: {
      ...summary,
      messages: camp.messages,
    },
  });
});

/**
 * GET /api/campaigns/:campaignId/status
 * Returns authoritative campaign status counters and processing state.
 * Implements canonical schema expected by Flutter client.
 */
router.get('/:campaignId/status', (req: Request, res: Response) => {
  const { campaignId } = req.params;
  const summary = campaignStore.getSummary(campaignId);

  if (!summary) {
    res.status(404).json({
      success: false,
      error: {
        code: 'CAMPAIGN_NOT_FOUND',
        message: `Campaign with ID '${campaignId}' was not found.`,
      },
    });
    return;
  }

  res.json({
    success: true,
    campaignId: summary.campaignId,
    campaignName: summary.campaignName,
    status: summary.status,
    total: summary.total,
    queued: summary.queued,
    accepted: summary.accepted,
    sent: summary.sent,
    delivered: summary.delivered,
    read: summary.read,
    failed: summary.failed,
    excludedOptOut: summary.excludedOptOut,
    campaign: summary,
  });
});


/**
 * GET /api/campaigns/:campaignId/events
 * Real-time SSE stream for live progress and message status updates.
 */
router.get('/:campaignId/events', (req: Request, res: Response) => {
  const { campaignId } = req.params;
  realtimeService.registerClient(campaignId, res);
});

export default router;
