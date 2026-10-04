import { env, getAuthorizedTestRecipients } from '../config/env';
import { CampaignSendRequest, StoredCampaign } from '../types/campaign';
import { StoredMessage } from '../types/message';
import { normalizeWhatsAppPhone, maskPhone } from '../utils/phone';
import { messageStore } from '../store/messageStore';
import { campaignStore } from '../store/campaignStore';
import { WhatsAppService } from './whatsappService';
import { realtimeService } from './realtimeService';

export class CampaignService {
  /**
   * Dispatches a campaign to Meta WhatsApp Cloud API with test mode safety checks.
   */
  public static async dispatchCampaign(req: CampaignSendRequest): Promise<{
    success: boolean;
    error?: { code: string; message: string };
    campaign?: StoredCampaign;
  }> {
    const { campaignId, campaignName, templateName = 'hello_world', templateLanguage = 'en_US', recipients, optedOutPhones = [] } = req;

    // 1. Enforce Test Mode Recipient Limit
    if (recipients.length > env.TEST_RECIPIENT_LIMIT) {
      return {
        success: false,
        error: {
          code: 'TEST_RECIPIENT_LIMIT',
          message: `WhatsApp Test Mode allows up to ${env.TEST_RECIPIENT_LIMIT} authorized recipients.`,
        },
      };
    }

    // 2. Duplicate send prevention / Idempotency check
    const existing = campaignStore.get(campaignId);
    if (existing && existing.status !== 'pending') {
      return {
        success: false,
        error: {
          code: 'DUPLICATE_CAMPAIGN',
          message: `Campaign ${campaignId} has already been submitted or processed.`,
        },
      };
    }

    const allowlist = getAuthorizedTestRecipients();
    const normalizedOptedOut = new Set(
      optedOutPhones.map((p) => normalizeWhatsAppPhone(p)).filter(Boolean) as string[]
    );

    console.log(`[Campaign] Initializing campaign ${campaignId} ('${campaignName}') with ${recipients.length} recipients`);

    // Prepare stored messages
    const storedMessages: StoredMessage[] = [];
    const now = new Date().toISOString();

    for (const r of recipients) {
      const internalId = `${campaignId}_${r.localCustomerId}`;
      const normalizedPhone = normalizeWhatsAppPhone(r.phone);

      const msg: StoredMessage = {
        id: internalId,
        campaignId,
        localCustomerId: r.localCustomerId,
        recipientName: r.name,
        normalizedPhone: normalizedPhone || r.phone,
        status: 'queued',
        createdAt: now,
        updatedAt: now,
      };

      storedMessages.push(msg);
      messageStore.upsert(msg);
    }

    const storedCampaign: StoredCampaign = {
      campaignId,
      campaignName,
      status: 'processing',
      total: recipients.length,
      accepted: 0,
      sent: 0,
      delivered: 0,
      read: 0,
      failed: 0,
      excludedOptOut: 0,
      messages: storedMessages,
      createdAt: now,
      updatedAt: now,
    };

    campaignStore.create(storedCampaign);

    // Process campaign sending asynchronously in background with controlled sequential delay
    setImmediate(() => {
      this.executeCampaignSend(campaignId, templateName, templateLanguage, allowlist, normalizedOptedOut);
    });

    return {
      success: true,
      campaign: storedCampaign,
    };
  }

  /**
   * Executes controlled sequential sending for the campaign.
   */
  private static async executeCampaignSend(
    campaignId: string,
    templateName: string,
    templateLanguage: string,
    allowlist: string[],
    optedOutSet: Set<string>
  ) {
    const campaign = campaignStore.get(campaignId);
    if (!campaign) return;

    console.log(`[Campaign] Starting controlled dispatch for ${campaignId}`);

    for (const msg of campaign.messages) {
      // Check 1: Valid normalized phone
      if (!msg.normalizedPhone || msg.normalizedPhone.length < 10) {
        console.warn(`[Campaign] Invalid phone for ${msg.recipientName}`);
        messageStore.updateStatus(msg.id, 'failed', undefined, {
          code: 400,
          title: 'Invalid Phone Number',
          message: 'Phone number could not be normalized for WhatsApp.',
        });
        realtimeService.broadcastMessageStatus({
          campaignId,
          phone: msg.normalizedPhone,
          status: 'failed',
          errorCode: 400,
          errorTitle: 'Invalid Phone Number',
        });
        continue;
      }

      // Check 2: Defensive Opt-Out check
      if (optedOutSet.has(msg.normalizedPhone)) {
        console.log(`[Campaign] Skipping ${maskPhone(msg.normalizedPhone)}: Customer is opted out`);
        messageStore.updateStatus(msg.id, 'excluded_opt_out', undefined, {
          title: 'Opted-Out',
          message: 'Customer is on the opt-out suppression list.',
        });
        realtimeService.broadcastMessageStatus({
          campaignId,
          phone: msg.normalizedPhone,
          status: 'excluded_opt_out',
        });
        continue;
      }

      // Check 3: Test mode allowlist check (if allowlist configured in environment)
      if (allowlist.length > 0 && !allowlist.includes(msg.normalizedPhone)) {
        console.warn(`[Campaign] Recipient ${maskPhone(msg.normalizedPhone)} not in authorized test allowlist`);
        messageStore.updateStatus(msg.id, 'failed', undefined, {
          code: 403,
          title: 'Unauthorized Test Recipient',
          message: 'Recipient phone number is not in authorized Meta test allowlist.',
        });
        realtimeService.broadcastMessageStatus({
          campaignId,
          phone: msg.normalizedPhone,
          status: 'failed',
          errorCode: 403,
          errorTitle: 'Unauthorized Test Recipient',
        });
        continue;
      }

      // Update to 'sending'
      messageStore.updateStatus(msg.id, 'sending');
      realtimeService.broadcastMessageStatus({
        campaignId,
        phone: msg.normalizedPhone,
        status: 'sending',
      });

      // Call Meta WhatsApp Cloud API
      const result = await WhatsAppService.sendTemplateMessage({
        recipientPhone: msg.normalizedPhone,
        recipientName: msg.recipientName,
        templateName,
        templateLanguage,
      });

      if (result.success && result.providerMessageId) {
        messageStore.updateStatus(msg.id, 'accepted', result.providerMessageId);
        realtimeService.broadcastMessageStatus({
          campaignId,
          phone: msg.normalizedPhone,
          status: 'accepted',
          providerMessageId: result.providerMessageId,
        });
      } else {
        messageStore.updateStatus(msg.id, 'failed', undefined, {
          code: result.errorCode,
          title: result.errorTitle,
          message: result.errorMessage,
        });
        realtimeService.broadcastMessageStatus({
          campaignId,
          phone: msg.normalizedPhone,
          status: 'failed',
          errorCode: result.errorCode,
          errorTitle: result.errorTitle,
        });

        // If Error 131031 (Account locked/restricted), stop campaign dispatch immediately
        if (result.errorCode === 131031) {
          console.error(`[Campaign] Account locked/restricted (Error 131031). Aborting remaining recipients.`);
          break;
        }
      }

      // Controlled delay between sends (e.g. 500ms) to respect rate limits
      await new Promise((resolve) => setTimeout(resolve, 500));
    }

    campaignStore.updateStatus(campaignId, 'completed');
    realtimeService.broadcastCampaignProgress(campaignId);
    console.log(`[Campaign] Completed dispatch for ${campaignId}`);
  }
}
