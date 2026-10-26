import { Router, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../config/env';
import { campaignSendSchema } from '../utils/validation';
import { CampaignService } from '../services/campaignService';
import { campaignStore } from '../store/campaignStore';
import { userStore } from '../store/userStore';
import { businessStore } from '../store/businessStore';
import { realtimeService } from '../services/realtimeService';
import {
  requireAuth,
  requireBusinessMembership,
  requireAuthorizedWhatsAppConnection,
  INITIAL_BUSINESS_ID,
} from '../middleware/authMiddleware';

const router = Router();

/**
 * GET /api/campaigns
 * Lists recent campaigns for the active business.
 */
router.get('/', requireAuth, requireBusinessMembership(), async (req: Request, res: Response) => {
  try {
    const limit = parseInt(req.query.limit as string || '50', 10);
    const summaries = await campaignStore.listSummaries(req.business!.id, limit);
    res.json({
      success: true,
      count: summaries.length,
      campaigns: summaries,
    });
  } catch (err: any) {
    console.error(`[Campaign] Database error in GET /:`, err?.message || err);
    res.status(500).json({
      success: false,
      error: {
        code: 'DATABASE_ERROR',
        message: err?.message || 'Database error occurred while fetching campaigns',
      },
    });
  }
});

/**
 * POST /api/campaigns/send
 * Dispatches a WhatsApp campaign scoped to active business.
 * Protected by requireAuth, requireBusinessMembership, and requireAuthorizedWhatsAppConnection.
 */
router.post(
  '/send',
  requireAuth,
  requireBusinessMembership(),
  requireAuthorizedWhatsAppConnection,
  async (req: Request, res: Response) => {
    try {
      const userEmail = req.user?.email?.toLowerCase().trim();

      // Schema Validation
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
            message:
              firstMessage !== 'Required' && !firstMessage.startsWith('Expected')
                ? firstMessage
                : `Invalid campaign data: ${errorFields.join(', ')}`,
            fields: errorFields,
          },
        });
        return;
      }

      // Dispatch Campaign strictly with authenticated businessId
      const result = await CampaignService.dispatchCampaign({
        ...parsed.data,
        campaignId: parsed.data.campaignId || `GB-${Date.now()}`,
        businessId: req.business!.id,
        clientRequestToken: parsed.data.clientRequestToken || undefined,
        templateLanguage: parsed.data.templateLanguage || 'en_US',
        templateComponents: (parsed.data.templateComponents ?? undefined) as any,
        userEmail,
        recipients: parsed.data.recipients.map((r, idx) => ({
          localCustomerId: r.localCustomerId || `cust_${idx + 1}`,
          name: r.name || 'Valued Customer',
          phone: r.phone,
          hasConsent: r.hasConsent ?? false,
          consentRecordedAt: r.consentRecordedAt || undefined,
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
    } catch (err: any) {
      console.error(`[Campaign] Database or system error in /send:`, err?.message || err);
      if (!res.headersSent) {
        res.status(500).json({
          success: false,
          error: {
            code: 'DATABASE_ERROR',
            message: err?.message || 'Database error occurred during campaign dispatch',
          },
        });
      }
    }
  }
);

/**
 * GET /api/campaigns/:campaignId
 * Returns the current authoritative campaign state, verified against business ownership.
 */
router.get('/:campaignId', requireAuth, requireBusinessMembership(), async (req: Request, res: Response) => {
  try {
    const { campaignId } = req.params;
    const camp = await campaignStore.get(campaignId, req.business!.id);

    if (!camp) {
      res.status(404).json({
        success: false,
        error: {
          code: 'CAMPAIGN_NOT_FOUND',
          message: `Campaign with ID '${campaignId}' was not found.`,
        },
      });
      return;
    }

    const summary = await campaignStore.getSummary(campaignId, req.business!.id);

    res.json({
      success: true,
      campaign: {
        ...(summary || camp),
        messages: camp.messages,
      },
    });
  } catch (err: any) {
    console.error(`[Campaign] Database error in GET /:campaignId:`, err?.message || err);
    if (!res.headersSent) {
      res.status(500).json({
        success: false,
        error: {
          code: 'DATABASE_ERROR',
          message: err?.message || 'Database error occurred while fetching campaign',
        },
      });
    }
  }
});

/**
 * GET /api/campaigns/:campaignId/status
 * Returns authoritative campaign status counters, verified against business ownership.
 */
router.get('/:campaignId/status', requireAuth, requireBusinessMembership(), async (req: Request, res: Response) => {
  try {
    const { campaignId } = req.params;
    const summary = await campaignStore.getSummary(campaignId, req.business!.id);

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
  } catch (err: any) {
    console.error(`[Campaign] Database error in GET /:campaignId/status:`, err?.message || err);
    if (!res.headersSent) {
      res.status(500).json({
        success: false,
        error: {
          code: 'DATABASE_ERROR',
          message: err?.message || 'Database error occurred while fetching campaign status',
        },
      });
    }
  }
});

/**
 * GET /api/campaigns/:campaignId/events
 * Real-time SSE stream for live progress and message status updates.
 * Authenticates via Bearer header OR ?token= query parameter, and validates campaign business ownership.
 */
router.get('/:campaignId/events', async (req: Request, res: Response) => {
  try {
    const { campaignId } = req.params;

    // 1. Resolve token from header or query param
    let token: string | undefined;
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith('Bearer ')) {
      token = authHeader.substring(7).trim();
    } else if (typeof req.query.token === 'string') {
      token = req.query.token.trim();
    }

    if (!token) {
      res.status(401).json({
        success: false,
        error: { code: 'UNAUTHORIZED', message: 'Authentication required for event stream' },
      });
      return;
    }

    let userId: string;
    try {
      const decoded = jwt.verify(token, env.JWT_SECRET) as { sub?: string; id?: string };
      userId = decoded.sub || decoded.id || '';
    } catch {
      res.status(401).json({
        success: false,
        error: { code: 'UNAUTHORIZED', message: 'Invalid or expired token' },
      });
      return;
    }

    // 2. Resolve businessId
    const businessIdHeader = (req.headers['x-business-id'] as string) || (req.query.business_id as string);
    let resolvedBizId: string | undefined;

    if (businessIdHeader) {
      const membership = await businessStore.getMember(businessIdHeader, userId);
      if (membership) {
        resolvedBizId = businessIdHeader;
      }
    } else {
      const userBusinesses = await businessStore.findByUserId(userId);
      const active = userBusinesses.filter((b) => b.isActive);
      if (active.length === 1) {
        resolvedBizId = active[0].id;
      } else {
        // Fallback for single-spa compatibility: only allow if user has verified membership in initial business
        const initialMember = await businessStore.getMember(INITIAL_BUSINESS_ID, userId);
        if (initialMember) {
          resolvedBizId = INITIAL_BUSINESS_ID;
        }
      }
    }

    if (!resolvedBizId) {
      res.status(403).json({
        success: false,
        error: { code: 'FORBIDDEN', message: 'Active business context required' },
      });
      return;
    }

    // 3. Verify campaign belongs to resolved business
    const camp = await campaignStore.get(campaignId, resolvedBizId);
    if (!camp) {
      res.status(404).json({
        success: false,
        error: { code: 'CAMPAIGN_NOT_FOUND', message: `Campaign '${campaignId}' not found.` },
      });
      return;
    }

    realtimeService.registerClient(campaignId, res);
  } catch (err: any) {
    console.error(`[Campaign] Error in SSE registration:`, err?.message || err);
    if (!res.headersSent) {
      res.status(500).json({
        success: false,
        error: {
          code: 'SSE_ERROR',
          message: 'Failed to establish event stream',
        },
      });
    }
  }
});

export default router;
