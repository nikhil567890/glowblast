import crypto from 'crypto';
import { env } from '../config/env';
import { MetaWebhookEntry } from '../types/whatsapp';
import { messageStore } from '../store/messageStore';
import { campaignStore } from '../store/campaignStore';
import { consentStore } from '../store/consentStore';
import { realtimeService } from './realtimeService';
import { maskPhone, normalizeWhatsAppPhone } from '../utils/phone';
import { getPool } from '../db/pool';
import { wabaConnectionStore } from '../store/wabaConnectionStore';
import { INITIAL_BUSINESS_ID } from '../middleware/authMiddleware';

export class WebhookService {
  /**
   * Validates Meta X-Hub-Signature-256 HMAC-SHA256 signature against META_APP_SECRET.
   * Uses timingSafeEqual to protect against timing attacks.
   *
   * Production Security Guarantees:
   * 1. In production, strictly requires a configured META_APP_SECRET and fails closed if missing.
   * 2. In development / test, permits payloads without signature ONLY if META_APP_SECRET is explicitly unset.
   *    If META_APP_SECRET is set in dev/test, signature verification is strictly enforced.
   * 3. Never logs secrets, webhook tokens, or signature hashes.
   */
  public static verifySignature(rawPayload: string | Buffer, signatureHeader?: string): boolean {
    const isProd = (process.env.NODE_ENV || env.NODE_ENV) === 'production';
    const appSecret = process.env.META_APP_SECRET || env.META_APP_SECRET;

    if (!appSecret || appSecret.trim() === '') {
      if (isProd) {
        console.error('[Webhook] Production security failure: META_APP_SECRET is missing. Rejecting webhook payload.');
        return false;
      }
      // Explicit non-production sandbox without configured app secret
      return true;
    }

    if (!signatureHeader || !signatureHeader.startsWith('sha256=')) {
      return false;
    }

    const providedSignature = signatureHeader.substring(7).trim();
    if (!providedSignature) {
      return false;
    }

    try {
      const hmac = crypto.createHmac('sha256', appSecret.trim());
      hmac.update(rawPayload);
      const expectedSignature = hmac.digest('hex');

      if (providedSignature.length !== expectedSignature.length) {
        return false;
      }

      return crypto.timingSafeEqual(
        Buffer.from(providedSignature, 'hex'),
        Buffer.from(expectedSignature, 'hex')
      );
    } catch (_) {
      return false;
    }
  }

  /**
   * Resolves the verified business tenant owning a receiving Meta phone_number_id.
   * Safety Guarantee: Never guesses or defaults to an arbitrary business.
   * Returns null if the phone_number_id is unknown or inactive.
   */
  public static async resolveBusinessForPhoneNumberId(
    phoneNumberId?: string
  ): Promise<string | null> {
    if (!phoneNumberId || typeof phoneNumberId !== 'string' || phoneNumberId.trim().length === 0) {
      return null;
    }

    const cleanPhoneId = phoneNumberId.trim();

    // 1. Check verified business WABA connections in database / store
    const registered = await wabaConnectionStore.findByPhoneNumberId(cleanPhoneId);
    if (registered && registered.isActive) {
      return registered.businessId;
    }

    // 2. Controlled compatibility fallback strictly for initial spa's legacy environment numbers
    if (
      cleanPhoneId === env.WHATSAPP_PHONE_NUMBER_ID ||
      cleanPhoneId === env.PROD_WHATSAPP_PHONE_NUMBER_ID
    ) {
      return INITIAL_BUSINESS_ID;
    }

    // Unknown or inactive phone-number ID: fail safe
    return null;
  }

  /**
   * Processes incoming Meta WhatsApp Cloud API webhook payload with strict tenant routing.
   * Idempotent deduplication is tracked in PostgreSQL webhook_events.
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

        // Resolve receiving Meta phone_number_id from change metadata
        const receivingPhoneId = val.metadata?.phone_number_id;
        const targetBusinessId = await this.resolveBusinessForPhoneNumberId(receivingPhoneId);

        if (!targetBusinessId) {
          console.warn(
            `[Webhook] Dropping webhook change for unknown or unregistered phone_number_id: '${receivingPhoneId || 'none'}'. Tenant isolation guaranteed.`
          );
          continue;
        }

        // 1. Process delivery status receipts (sent, delivered, read, failed)
        if (val.statuses && Array.isArray(val.statuses)) {
          for (const statusObj of val.statuses) {
            const providerMessageId = statusObj.id;
            const newStatus = statusObj.status;
            const recipientId = statusObj.recipient_id;
            const bizOpaque = (statusObj as any).biz_opaque_callback_data;

            if (!providerMessageId || !newStatus) continue;

            const dedupKey = `status:${targetBusinessId}:${providerMessageId}:${newStatus}`;

            // Webhook event deduplication in PostgreSQL
            let dedupRes;
            try {
              dedupRes = await pool.query<{ dedup_key: string }>(
                `INSERT INTO webhook_events (dedup_key, event_type, provider_message_id, status, business_id, payload)
                 VALUES ($1, 'status', $2, $3, $4, $5)
                 ON CONFLICT (dedup_key) DO NOTHING
                 RETURNING dedup_key;`,
                [dedupKey, providerMessageId, newStatus, targetBusinessId, JSON.stringify(statusObj)]
              );
            } catch (colErr: any) {
              if (colErr.code === '42703') {
                dedupRes = await pool.query<{ dedup_key: string }>(
                  `INSERT INTO webhook_events (dedup_key, event_type, provider_message_id, status, payload)
                   VALUES ($1, 'status', $2, $3, $4)
                   ON CONFLICT (dedup_key) DO NOTHING
                   RETURNING dedup_key;`,
                  [dedupKey, providerMessageId, newStatus, JSON.stringify(statusObj)]
                );
              } else {
                throw colErr;
              }
            }

            if (dedupRes.rows.length === 0) {
              console.log(`[Webhook] Duplicate status event ${dedupKey} ignored (idempotent)`);
              continue;
            }

            console.log(
              `[Webhook] Provider Status [biz=${targetBusinessId}]: ${providerMessageId} (${maskPhone(recipientId)}) -> ${newStatus}`
            );

            // Find matching stored message strictly within targetBusinessId
            let msg = await messageStore.getByProviderId(providerMessageId, targetBusinessId);
            if (!msg && bizOpaque && typeof bizOpaque === 'string') {
              msg = await messageStore.get(bizOpaque, targetBusinessId);
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

              // Recalculate and persist updated campaign status scoped to this business
              await campaignStore.recalculateAndSaveCampaignStatus(msg.campaignId, targetBusinessId);

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
              console.log(`[Webhook] Message ${providerMessageId} not found under business ${targetBusinessId}`);
            }
          }
        }

        // 2. Process incoming customer messages (STOP keywords & Inbound Replies)
        if (val.messages && Array.isArray(val.messages)) {
          for (const msgObj of val.messages) {
            if (!msgObj.id) continue;

            const dedupKey = `message:${targetBusinessId}:${msgObj.id}`;

            let dedupRes;
            try {
              dedupRes = await pool.query<{ dedup_key: string }>(
                `INSERT INTO webhook_events (dedup_key, event_type, provider_message_id, status, business_id, payload)
                 VALUES ($1, 'message', $2, NULL, $3, $4)
                 ON CONFLICT (dedup_key) DO NOTHING
                 RETURNING dedup_key;`,
                [dedupKey, msgObj.id, targetBusinessId, JSON.stringify(msgObj)]
              );
            } catch (colErr: any) {
              if (colErr.code === '42703') {
                dedupRes = await pool.query<{ dedup_key: string }>(
                  `INSERT INTO webhook_events (dedup_key, event_type, provider_message_id, status, payload)
                   VALUES ($1, 'message', $2, NULL, $3)
                   ON CONFLICT (dedup_key) DO NOTHING
                   RETURNING dedup_key;`,
                  [dedupKey, msgObj.id, JSON.stringify(msgObj)]
                );
              } else {
                throw colErr;
              }
            }

            if (dedupRes.rows.length === 0) {
              console.log(`[Webhook] Duplicate inbound message ${dedupKey} ignored (idempotent)`);
              continue;
            }

            console.log(`[Webhook] Inbound message [biz=${targetBusinessId}] from ${maskPhone(msgObj.from)}: ${msgObj.id}`);
            const textBody = (msgObj.text?.body || '').trim().toUpperCase();

            // Check for explicit opt-out keywords (scoped strictly to targetBusinessId)
            if (['STOP', 'UNSUBSCRIBE', 'OPT OUT', 'OPTOUT'].includes(textBody)) {
              console.log(
                `[Webhook] Customer ${maskPhone(msgObj.from)} opted out via keyword '${textBody}' for business ${targetBusinessId}`
              );
              await consentStore.recordConsent({
                phone: msgObj.from,
                status: 'opted_out',
                source: 'inbound_whatsapp_keyword',
                updatedBy: 'meta_webhook',
                evidence: `Customer sent keyword ${textBody}`,
                inboundWebhookId: msgObj.id,
                businessId: targetBusinessId,
              });
            } else {
              // 3. Process genuine inbound customer reply and associate with recent campaign recipient OF THIS BUSINESS
              const normalizedSender = normalizeWhatsAppPhone(msgObj.from);
              if (normalizedSender) {
                let matchingMsg: { id: string; campaign_id: string; local_customer_id: string; normalized_phone: string } | undefined;

                // Priority 1: Direct reply via Meta context.id (scoped to targetBusinessId)
                const contextMsgId = (msgObj as any).context?.id;
                if (contextMsgId && typeof contextMsgId === 'string') {
                  try {
                    const ctxRes = await pool.query<{ id: string; campaign_id: string; local_customer_id: string; normalized_phone: string }>(
                      `SELECT id, campaign_id, local_customer_id, normalized_phone
                       FROM campaign_messages
                       WHERE provider_message_id = $1
                         AND (business_id = $2 OR (business_id IS NULL AND $2 = 'a0000000-0000-4000-8000-000000000001'))
                       LIMIT 1;`,
                      [contextMsgId, targetBusinessId]
                    );
                    if (ctxRes.rows.length > 0) {
                      matchingMsg = ctxRes.rows[0];
                    }
                  } catch (colErr: any) {
                    if (colErr.code === '42703') {
                      if (targetBusinessId === INITIAL_BUSINESS_ID) {
                        const ctxRes = await pool.query<{ id: string; campaign_id: string; local_customer_id: string; normalized_phone: string }>(
                          `SELECT id, campaign_id, local_customer_id, normalized_phone
                           FROM campaign_messages
                           WHERE provider_message_id = $1
                           LIMIT 1;`,
                          [contextMsgId]
                        );
                        if (ctxRes.rows.length > 0) matchingMsg = ctxRes.rows[0];
                      }
                    } else {
                      throw colErr;
                    }
                  }
                }

                // Priority 2: Inbound within 24 hours of a sent campaign to this recipient (scoped to targetBusinessId)
                if (!matchingMsg) {
                  try {
                    const recentRes = await pool.query<{ id: string; campaign_id: string; local_customer_id: string; normalized_phone: string }>(
                      `SELECT id, campaign_id, local_customer_id, normalized_phone
                       FROM campaign_messages
                       WHERE normalized_phone = $1
                         AND (business_id = $2 OR (business_id IS NULL AND $2 = 'a0000000-0000-4000-8000-000000000001'))
                         AND created_at >= NOW() - INTERVAL '24 hours'
                       ORDER BY created_at DESC
                       LIMIT 1;`,
                      [normalizedSender, targetBusinessId]
                    );
                    if (recentRes.rows.length > 0) {
                      matchingMsg = recentRes.rows[0];
                    }
                  } catch (colErr: any) {
                    if (colErr.code === '42703') {
                      if (targetBusinessId === INITIAL_BUSINESS_ID) {
                        const recentRes = await pool.query<{ id: string; campaign_id: string; local_customer_id: string; normalized_phone: string }>(
                          `SELECT id, campaign_id, local_customer_id, normalized_phone
                           FROM campaign_messages
                           WHERE normalized_phone = $1
                             AND created_at >= NOW() - INTERVAL '24 hours'
                           ORDER BY created_at DESC
                           LIMIT 1;`,
                          [normalizedSender]
                        );
                        if (recentRes.rows.length > 0) matchingMsg = recentRes.rows[0];
                      }
                    } else {
                      throw colErr;
                    }
                  }
                }

                if (matchingMsg) {
                  const replyDedupKey = `reply:${targetBusinessId}:${msgObj.id}:${matchingMsg.campaign_id}`;
                  let replyDedup;
                  try {
                    replyDedup = await pool.query(
                      `INSERT INTO webhook_events (dedup_key, event_type, provider_message_id, status, business_id, payload)
                       VALUES ($1, 'message', $2, 'replied', $3, $4)
                       ON CONFLICT (dedup_key) DO NOTHING
                       RETURNING dedup_key;`,
                      [replyDedupKey, msgObj.id, targetBusinessId, JSON.stringify(msgObj)]
                    );
                  } catch (colErr: any) {
                    if (colErr.code === '42703') {
                      replyDedup = await pool.query(
                        `INSERT INTO webhook_events (dedup_key, event_type, provider_message_id, status, payload)
                         VALUES ($1, 'message', $2, 'replied', $3)
                         ON CONFLICT (dedup_key) DO NOTHING
                         RETURNING dedup_key;`,
                        [replyDedupKey, msgObj.id, JSON.stringify(msgObj)]
                      );
                    } else {
                      throw colErr;
                    }
                  }

                  if (replyDedup.rows.length > 0) {
                    console.log(
                      `[Webhook] Associated verified reply [biz=${targetBusinessId}] from ${maskPhone(msgObj.from)} to campaign ${matchingMsg.campaign_id}`
                    );
                    await messageStore.recordReply(matchingMsg.id);
                    await campaignStore.recalculateAndSaveCampaignStatus(matchingMsg.campaign_id, targetBusinessId);

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
