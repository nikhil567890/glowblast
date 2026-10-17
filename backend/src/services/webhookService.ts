import { MetaWebhookEntry } from '../types/whatsapp';
import { messageStore } from '../store/messageStore';
import { campaignStore } from '../store/campaignStore';
import { realtimeService } from './realtimeService';
import { maskPhone, normalizeWhatsAppPhone } from '../utils/phone';
import { consentStore } from '../store/consentStore';
import { getPool } from '../db/pool';

export class WebhookService {
  /**
   * Processes incoming Meta WhatsApp Cloud API webhook payload idempotently using PostgreSQL webhook_events.
   */
  public static async processWebhookPayload(payload: { object: string; entry: MetaWebhookEntry[] }): Promise<void> {
    if (payload.object !== 'whatsapp_business_account' || !payload.entry) {
      return;
    }

    const pool = getPool();

    for (const entry of payload.entry) {
      for (const change of entry.changes) {
        const val = change.value;
        if (!val || val.messaging_product !== 'whatsapp') continue;

        // 1. Process delivery status receipts (sent, delivered, read, failed)
        if (val.statuses && Array.isArray(val.statuses)) {
          for (const statusObj of val.statuses) {
            const providerMessageId = statusObj.id;
            const newStatus = statusObj.status;
            const recipientId = statusObj.recipient_id;
            const bizOpaque = (statusObj as any).biz_opaque_callback_data;

            if (!providerMessageId || !newStatus) continue;

            const dedupKey = `status:${providerMessageId}:${newStatus}`;

            // Webhook event deduplication in PostgreSQL
            const dedupRes = await pool.query<{ dedup_key: string }>(
              `INSERT INTO webhook_events (dedup_key, event_type, provider_message_id, status, payload)
               VALUES ($1, 'status', $2, $3, $4)
               ON CONFLICT (dedup_key) DO NOTHING
               RETURNING dedup_key;`,
              [dedupKey, providerMessageId, newStatus, JSON.stringify(statusObj)]
            );

            if (dedupRes.rows.length === 0) {
              console.log(`[Webhook] Duplicate status event ${dedupKey} ignored (idempotent)`);
              continue;
            }

            console.log(
              `[Webhook] Provider Status: ${providerMessageId} (${maskPhone(recipientId)}) -> ${newStatus}`
            );

            // Find matching stored message by provider ID or biz_opaque_callback_data (internal message ID)
            let msg = await messageStore.getByProviderId(providerMessageId);
            if (!msg && bizOpaque && typeof bizOpaque === 'string') {
              msg = await messageStore.get(bizOpaque);
            }

            if (msg) {
              let errorObj: { code?: number; title?: string; message?: string } | undefined;
              if (newStatus === 'failed' && statusObj.errors && statusObj.errors.length > 0) {
                const err = statusObj.errors[0];
                errorObj = {
                  code: err.code,
                  title: err.title,
                  message: err.message || err.error_data?.details,
                };
                console.error(`[Webhook] Message failed. Code: ${err.code}, Title: ${err.title}`);
              }

              // Update in store (enforcing monotonic status transitions and preserving provider ID)
              await messageStore.updateStatus(msg.id, newStatus, providerMessageId, errorObj);

              // Recalculate and persist updated campaign status
              await campaignStore.recalculateAndSaveCampaignStatus(msg.campaignId);

              // Broadcast via SSE to connected clients
              realtimeService.broadcastMessageStatus({
                campaignId: msg.campaignId,
                phone: msg.normalizedPhone,
                status: newStatus,
                providerMessageId,
                errorCode: errorObj?.code,
                errorTitle: errorObj?.title,
              });
            } else {
              console.log(`[Webhook] Message ${providerMessageId} not found in store`);
            }
          }
        }

        // 2. Process incoming customer messages (STOP keywords & Inbound Replies)
        if (val.messages && Array.isArray(val.messages)) {
          for (const msgObj of val.messages) {
            if (!msgObj.id) continue;

            const dedupKey = `message:${msgObj.id}`;

            const dedupRes = await pool.query<{ dedup_key: string }>(
              `INSERT INTO webhook_events (dedup_key, event_type, provider_message_id, status, payload)
               VALUES ($1, 'message', $2, NULL, $3)
               ON CONFLICT (dedup_key) DO NOTHING
               RETURNING dedup_key;`,
              [dedupKey, msgObj.id, JSON.stringify(msgObj)]
            );

            if (dedupRes.rows.length === 0) {
              console.log(`[Webhook] Duplicate inbound message ${dedupKey} ignored (idempotent)`);
              continue;
            }

            console.log(`[Webhook] Inbound customer message from ${maskPhone(msgObj.from)}: ${msgObj.id}`);
            const textBody = (msgObj.text?.body || '').trim().toUpperCase();

            // Check for explicit opt-out keywords
            if (['STOP', 'UNSUBSCRIBE', 'OPT OUT', 'OPTOUT'].includes(textBody)) {
              console.log(`[Webhook] Customer ${maskPhone(msgObj.from)} requested opt-out via keyword '${textBody}'`);
              await consentStore.recordOptOut({
                phone: msgObj.from,
                source: 'inbound_whatsapp_keyword',
                updatedBy: 'meta_webhook',
                reason: `Customer sent keyword ${textBody}`,
                inboundWebhookId: msgObj.id,
              });
            } else {
              // 3. Process genuine inbound customer reply and associate with recent campaign recipient
              const normalizedSender = normalizeWhatsAppPhone(msgObj.from);
              if (normalizedSender) {
                let matchingMsg: { id: string; campaign_id: string; local_customer_id: string; normalized_phone: string } | undefined;

                // Priority 1: Direct reply via Meta context.id
                const contextMsgId = (msgObj as any).context?.id;
                if (contextMsgId && typeof contextMsgId === 'string') {
                  const ctxRes = await pool.query<{ id: string; campaign_id: string; local_customer_id: string; normalized_phone: string }>(
                    `SELECT id, campaign_id, local_customer_id, normalized_phone
                     FROM campaign_messages
                     WHERE provider_message_id = $1
                     LIMIT 1;`,
                    [contextMsgId]
                  );
                  if (ctxRes.rows.length > 0) {
                    matchingMsg = ctxRes.rows[0];
                  }
                }

                // Priority 2: Inbound within 24 hours of a sent campaign to this recipient
                if (!matchingMsg) {
                  const recentRes = await pool.query<{ id: string; campaign_id: string; local_customer_id: string; normalized_phone: string }>(
                    `SELECT id, campaign_id, local_customer_id, normalized_phone
                     FROM campaign_messages
                     WHERE normalized_phone = $1 AND created_at >= NOW() - INTERVAL '24 hours'
                     ORDER BY created_at DESC
                     LIMIT 1;`,
                    [normalizedSender]
                  );
                  if (recentRes.rows.length > 0) {
                    matchingMsg = recentRes.rows[0];
                  }
                }

                if (matchingMsg) {
                  const replyDedupKey = `reply:${msgObj.id}:${matchingMsg.campaign_id}`;
                  const replyDedup = await pool.query(
                    `INSERT INTO webhook_events (dedup_key, event_type, provider_message_id, status, payload)
                     VALUES ($1, 'message', $2, 'replied', $3)
                     ON CONFLICT (dedup_key) DO NOTHING
                     RETURNING dedup_key;`,
                    [replyDedupKey, msgObj.id, JSON.stringify(msgObj)]
                  );

                  if (replyDedup.rows.length > 0) {
                    console.log(`[Webhook] Associated verified reply from ${maskPhone(msgObj.from)} to campaign ${matchingMsg.campaign_id}`);
                    await messageStore.recordReply(matchingMsg.id);
                    await campaignStore.recalculateAndSaveCampaignStatus(matchingMsg.campaign_id);

                    realtimeService.broadcastMessageStatus({
                      campaignId: matchingMsg.campaign_id,
                      phone: matchingMsg.normalized_phone,
                      status: 'replied' as any,
                      providerMessageId: msgObj.id,
                    });
                  } else {
                    console.log(`[Webhook] Duplicate reply event ${replyDedupKey} ignored (idempotent)`);
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
