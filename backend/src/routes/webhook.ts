import { Router, Request, Response } from 'express';
import { env, getWebhookVerifyToken } from '../config/env';
import { WebhookService } from '../services/webhookService';

const router = Router();

/**
 * GET /api/webhook/whatsapp
 * Meta WhatsApp Cloud API Webhook verification challenge.
 * Accepts either META_VERIFY_TOKEN or WHATSAPP_WEBHOOK_VERIFY_TOKEN for consistent environment configuration.
 */
router.get('/whatsapp', (req: Request, res: Response) => {
  const mode = req.query['hub.mode'];
  const token = req.query['hub.verify_token'];
  const challenge = req.query['hub.challenge'];

  const expectedToken = getWebhookVerifyToken();
  const tokenMatches =
    token === expectedToken ||
    token === env.META_VERIFY_TOKEN ||
    (env.WHATSAPP_WEBHOOK_VERIFY_TOKEN && token === env.WHATSAPP_WEBHOOK_VERIFY_TOKEN);

  if (mode === 'subscribe' && tokenMatches) {
    console.log('[Webhook] Meta verification successful');
    res.status(200).send(challenge);
  } else {
    console.warn('[Webhook] Verification failed. Token mismatch or invalid mode.');
    res.sendStatus(403);
  }
});

/**
 * POST /api/webhook/whatsapp
 * Receives delivery status receipts (sent, delivered, read, failed) from Meta.
 */
router.post('/whatsapp', async (req: Request, res: Response) => {
  try {
    await WebhookService.processWebhookPayload(req.body);
    // Meta requires immediate 200 OK
    res.sendStatus(200);
  } catch (err: any) {
    console.error(`[Webhook] Error processing webhook payload: ${err.message}`);
    res.sendStatus(200); // Acknowledge to prevent Meta retrying continuously
  }
});

export default router;
