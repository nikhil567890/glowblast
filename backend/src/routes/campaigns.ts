import { Router, Request, Response } from 'express';
import { campaignSendSchema } from '../utils/validation';
import { CampaignService } from '../services/campaignService';
import { campaignStore } from '../store/campaignStore';
import { realtimeService } from '../services/realtimeService';

const router = Router();

/**
 * POST /api/campaigns/send
 * Dispatches a WhatsApp campaign (max 5 recipients in test mode).
 */
router.post('/send', async (req: Request, res: Response) => {
  const parsed = campaignSendSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Invalid campaign payload format',
        details: parsed.error.format(),
      },
    });
    return;
  }

  const result = await CampaignService.dispatchCampaign(parsed.data);

  if (!result.success) {
    res.status(400).json({
      success: false,
      error: result.error,
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
    campaign: summary,
  });
});

/**
 * GET /api/campaigns/:campaignId/status
 * Returns campaign status counters and processing state.
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
    status: summary.status,
    total: summary.total,
    accepted: summary.accepted,
    sent: summary.sent,
    delivered: summary.delivered,
    read: summary.read,
    failed: summary.failed,
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
