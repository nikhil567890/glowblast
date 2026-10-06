import { MetaWebhookEntry } from '../types/whatsapp';
import { messageStore } from '../store/messageStore';
import { campaignStore } from '../store/campaignStore';
import { realtimeService } from './realtimeService';
import { maskPhone } from '../utils/phone';

export class WebhookService {
  /**
   * Processes incoming Meta WhatsApp Cloud API webhook event.
   */
  public static processWebhookPayload(payload: { object: string; entry: MetaWebhookEntry[] }): void {
    if (payload.object !== 'whatsapp_business_account' || !payload.entry) {
      return;
    }

    for (const entry of payload.entry) {
      for (const change of entry.changes) {
        const val = change.value;
        if (!val || val.messaging_product !== 'whatsapp') continue;

        // Process status updates (sent, delivered, read, failed)
        if (val.statuses && Array.isArray(val.statuses)) {
          for (const statusObj of val.statuses) {
            const providerMessageId = statusObj.id;
            const newStatus = statusObj.status;
            const recipientId = statusObj.recipient_id;

            console.log(
              `[Webhook] Provider Status: ${providerMessageId} (${maskPhone(recipientId)}) -> ${newStatus}`
            );

            // Find matching stored message by provider ID
            const msg = messageStore.getByProviderId(providerMessageId);
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

              // Update in store (enforcing monotonic hierarchy and idempotency)
              messageStore.updateStatus(msg.id, newStatus, providerMessageId, errorObj);

              // Recalculate and persist updated campaign status
              campaignStore.recalculateAndSaveCampaignStatus(msg.campaignId);

              // Broadcast via SSE to connected APK client
              realtimeService.broadcastMessageStatus({
                campaignId: msg.campaignId,
                phone: msg.normalizedPhone,
                status: newStatus,
                providerMessageId,
                errorCode: errorObj?.code,
                errorTitle: errorObj?.title,
              });
            } else {
              console.log(`[Webhook] Message ${providerMessageId} not found in local store (or sent externally)`);
            }
          }
        }

        // Incoming messages (replies from customers)
        if (val.messages && Array.isArray(val.messages)) {
          for (const msgObj of val.messages) {
            console.log(`[Webhook] Inbound customer message from ${maskPhone(msgObj.from)}: ${msgObj.id}`);
            // Note: Inbound messages can be tracked for replies if customer responds
          }
        }
      }
    }
  }
}
