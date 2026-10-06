import { env, getAuthorizedTestRecipients } from '../config/env';
import { CampaignSendRequest, StoredCampaign } from '../types/campaign';
import { StoredMessage } from '../types/message';
import { normalizeWhatsAppPhone, maskPhone } from '../utils/phone';
import { messageStore } from '../store/messageStore';
import { campaignStore } from '../store/campaignStore';
import { templateStore } from '../store/templateStore';
import { WhatsAppService } from './whatsappService';
import { realtimeService } from './realtimeService';

export class CampaignService {
  /**
   * Dispatches a campaign to Meta WhatsApp Cloud API with test mode safety checks and approved template validation.
   */
  public static async dispatchCampaign(req: CampaignSendRequest): Promise<{
    success: boolean;
    error?: { code: string; message: string };
    campaign?: StoredCampaign;
  }> {
    const {
      campaignId,
      campaignName,
      businessName,
      templateId,
      templateName,
      templateLanguage = 'en_US',
      templateVariables = [],
      templateComponents,
      recipients,
      optedOutPhones = [],
    } = req;

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

    // 3. Validate template and approval status
    if (!templateName || templateName.trim().length === 0) {
      return {
        success: false,
        error: {
          code: 'MISSING_TEMPLATE',
          message: 'A valid WhatsApp template must be selected.',
        },
      };
    }

    const templateLookupKey = templateId || templateName;
    const template = templateStore.findByIdOrName(templateLookupKey);

    let effectiveMetaTemplateName = templateName.trim();
    let effectiveTemplateLanguage = templateLanguage || 'en_US';
    let effectiveVariables = [...templateVariables];

    if (template) {
      if (template.status !== 'approved') {
        console.warn(
          `[Campaign] Blocked dispatch: template '${template.displayName}' (${template.name}) has status '${template.status}'.`
        );
        return {
          success: false,
          error: {
            code: 'TEMPLATE_NOT_APPROVED',
            message: `This GlowBlast template is not connected to an approved WhatsApp template yet (status: ${template.status}).`,
          },
        };
      }
      effectiveMetaTemplateName = template.name;
      effectiveTemplateLanguage = template.language || effectiveTemplateLanguage;
      if (effectiveVariables.length === 0 && template.variables) {
        effectiveVariables = template.variables;
      }
    } else {
      // If template is not in templateStore, only 'hello_world' is permitted as explicit Meta test template
      if (templateName !== 'hello_world') {
        console.warn(
          `[Campaign] Blocked dispatch: template '${templateName}' has no valid Meta mapping in template store.`
        );
        return {
          success: false,
          error: {
            code: 'UNMAPPED_TEMPLATE',
            message: 'This GlowBlast template is not connected to an approved WhatsApp template yet.',
          },
        };
      }
    }

    const allowlist = getAuthorizedTestRecipients();
    const normalizedOptedOut = new Set(
      optedOutPhones.map((p) => normalizeWhatsAppPhone(p)).filter(Boolean) as string[]
    );

    console.log(
      `[Campaign] Initializing campaign ${campaignId} ('${campaignName}') with ${recipients.length} recipients, Meta template='${effectiveMetaTemplateName}' (${effectiveTemplateLanguage})`
    );

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
        templateName: effectiveMetaTemplateName,
        templateLanguage: effectiveTemplateLanguage,
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
      templateName: effectiveMetaTemplateName,
      templateLanguage: effectiveTemplateLanguage,
      total: recipients.length,
      queued: recipients.length,
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
      this.executeCampaignSend({
        campaignId,
        templateName: effectiveMetaTemplateName,
        templateLanguage: effectiveTemplateLanguage,
        variables: effectiveVariables,
        businessName,
        allowlist,
        optedOutSet: normalizedOptedOut,
        templateComponents,
        templateRef: template,
      });
    });

    return {
      success: true,
      campaign: storedCampaign,
    };
  }

  /**
   * Executes controlled sequential sending for the campaign with per-recipient parameter resolution.
   */
  private static async executeCampaignSend(params: {
    campaignId: string;
    templateName: string;
    templateLanguage: string;
    variables: string[];
    businessName?: string;
    allowlist: string[];
    optedOutSet: Set<string>;
    templateComponents?: Array<{
      type: string;
      parameters: Array<{
        type: string;
        text?: string;
        [key: string]: any;
      }>;
    }>;
    templateRef?: any;
  }) {
    const {
      campaignId,
      templateName,
      templateLanguage,
      variables,
      businessName,
      allowlist,
      optedOutSet,
      templateComponents,
      templateRef,
    } = params;

    const campaign = campaignStore.get(campaignId);
    if (!campaign) return;

    console.log(`[Campaign] Starting controlled dispatch for ${campaignId} using template '${templateName}'`);

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
        const masked = maskPhone(msg.normalizedPhone);
        console.warn(`[Campaign] Recipient ${masked} not in authorized test allowlist`);
        messageStore.updateStatus(msg.id, 'failed', undefined, {
          code: 403,
          title: 'Unauthorized Test Recipient',
          message: `Recipient ${masked} is not in the authorized Meta test allowlist. Add this number in Meta App Dashboard > WhatsApp > API Setup > To.`,
          details: 'Recipient is not authorized for the current Meta WhatsApp test environment.',
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

      // Construct recipient-specific components
      let resolvedComponents = templateComponents;

      // If template is 'hello_world', Meta rejects any components
      if (templateName === 'hello_world') {
        resolvedComponents = undefined;
      } else if (!resolvedComponents && variables.length > 0) {
        // Build Meta parameter array mapped from variable definitions
        const bodyParameters = variables.map((v) => {
          const vLower = v.toLowerCase();
          let textVal = '';
          if (vLower === 'name' || vLower === 'customer_name' || vLower === 'client') {
            textVal = msg.recipientName || 'Client';
          } else if (vLower === 'business_name' || vLower === 'spa_name') {
            textVal = businessName || 'Our Spa & Wellness';
          } else if (templateRef?.exampleValues?.[v]) {
            textVal = templateRef.exampleValues[v];
          } else {
            textVal = v;
          }
          return {
            type: 'text',
            text: textVal,
          };
        });

        resolvedComponents = [
          {
            type: 'body',
            parameters: bodyParameters,
          },
        ];
      }

      // Call Meta WhatsApp Cloud API
      const result = await WhatsAppService.sendTemplateMessage({
        recipientPhone: msg.normalizedPhone,
        recipientName: msg.recipientName,
        templateName,
        templateLanguage,
        templateComponents: resolvedComponents,
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
          details: result.errorDetails,
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

      // Controlled delay between sends (500ms) to respect rate limits
      await new Promise((resolve) => setTimeout(resolve, 500));
    }

    // Authoritative status calculation based on real message statuses
    const finalSummary = campaignStore.recalculateAndSaveCampaignStatus(campaignId);
    realtimeService.broadcastCampaignProgress(campaignId);
    console.log(
      `[Campaign] Completed dispatch for ${campaignId}. Authoritative status: ${finalSummary?.status} (Total: ${finalSummary?.total}, Accepted: ${finalSummary?.accepted}, Failed: ${finalSummary?.failed})`
    );
  }
}
