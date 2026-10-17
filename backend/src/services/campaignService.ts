import {
  env,
  getAuthorizedTestRecipients,
  isProductionConfigured,
  isEmailAuthorizedForProduction,
} from '../config/env';
import { CampaignSendRequest, StoredCampaign } from '../types/campaign';
import { StoredMessage } from '../types/message';
import { normalizeWhatsAppPhone, maskPhone } from '../utils/phone';
import { messageStore } from '../store/messageStore';
import { campaignStore } from '../store/campaignStore';
import { templateStore } from '../store/templateStore';
import { consentStore } from '../store/consentStore';
import { WhatsAppService, WhatsAppCredentials } from './whatsappService';
import { realtimeService } from './realtimeService';
import { getPool } from '../db/pool';

export class CampaignService {
  /**
   * Dispatches a campaign with atomic PostgreSQL transaction setup and post-commit message claims.
   */
  public static async dispatchCampaign(req: CampaignSendRequest): Promise<{
    success: boolean;
    error?: { code: string; message: string };
    campaign?: StoredCampaign;
  }> {
    const effectiveCampaignId = req.campaignId?.trim() || `GB-${Date.now()}`;
    const effectiveCampaignName = req.campaignName.trim();
    const effectiveBusinessName = req.businessName?.trim() || undefined;
    const templateId = req.templateId?.trim() || undefined;
    const templateName = req.templateName.trim();
    const effectiveTemplateLanguage = req.templateLanguage?.trim() || 'en_US';
    const effectiveVariables = req.templateVariables ? [...req.templateVariables] : [];
    const optedOutPhones = req.optedOutPhones || [];
    const normalizedOptedOut = new Set(
      optedOutPhones.map((p) => normalizeWhatsAppPhone(p)).filter(Boolean) as string[]
    );
    const templateComponents = req.templateComponents || undefined;
    const recipients = req.recipients;
    const mode = req.mode === 'production' ? 'production' : req.mode === 'demo' ? 'demo' : 'test';
    const clientRequestToken =
      req.clientRequestToken?.trim() ||
      req.campaignId?.trim() ||
      `tok_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;

    // 0. Demo Mode Guard (Demo must run client-side only)
    if (mode === 'demo') {
      console.warn(`[Campaign] Rejected: reason=DEMO_MODE_NOT_ALLOWED`);
      return {
        success: false,
        error: {
          code: 'DEMO_MODE_NOT_ALLOWED',
          message: 'Demo campaigns must be simulated locally and are not processed on the server.',
        },
      };
    }

    // 1. Validate template presence
    if (!templateName || templateName.trim().length === 0) {
      console.warn(`[Campaign] Rejected: reason=TEMPLATE_NOT_FOUND`);
      return {
        success: false,
        error: {
          code: 'TEMPLATE_NOT_FOUND',
          message: 'A valid WhatsApp template must be selected.',
        },
      };
    }

    const templateLookupKey = templateId || templateName;
    const template = await templateStore.findByIdOrName(templateLookupKey, mode);

    let effectiveMetaTemplateName = templateName.trim();
    let finalTemplateLanguage = effectiveTemplateLanguage;
    let finalVariables = [...effectiveVariables];

    // Mode-specific credential & authorization routing
    let targetCredentials: WhatsAppCredentials;
    let normalizedConsentedPhones: string[] = [];

    if (mode === 'production') {
      // --- PRODUCTION SAFETY CHECKS ---

      // Production Safety Check 1: Kill-switch (ENABLE_PRODUCTION_CAMPAIGNS)
      if (!env.ENABLE_PRODUCTION_CAMPAIGNS) {
        console.warn(`[Campaign] Rejected: reason=PRODUCTION_MODE_DISABLED`);
        return {
          success: false,
          error: {
            code: 'PRODUCTION_MODE_DISABLED',
            message:
              'Live production broadcasts are currently disabled on the backend (ENABLE_PRODUCTION_CAMPAIGNS=false).',
          },
        };
      }

      // Production Safety Check 2: Production Credentials presence
      if (!isProductionConfigured()) {
        console.warn(`[Campaign] Rejected: reason=PRODUCTION_CREDENTIALS_MISSING`);
        return {
          success: false,
          error: {
            code: 'PRODUCTION_CREDENTIALS_MISSING',
            message:
              'Production WhatsApp credentials (PROD_WHATSAPP_PHONE_NUMBER_ID, PROD_WHATSAPP_ACCESS_TOKEN) are not fully configured in server environment.',
          },
        };
      }

      // Production Safety Check 3: Email Authorization (PRODUCTION_ALLOWED_EMAILS)
      if (!isEmailAuthorizedForProduction(req.userEmail || undefined)) {
        console.warn(
          `[Campaign] Rejected: reason=UNAUTHORIZED_PRODUCTION_USER email=${req.userEmail || 'unknown'}`
        );
        return {
          success: false,
          error: {
            code: 'UNAUTHORIZED_PRODUCTION_USER',
            message: 'Your authenticated account email is not authorized for live production broadcasts.',
          },
        };
      }

      // Production Safety Check 4: Test template 'hello_world' is disallowed in production
      if (templateName === 'hello_world') {
        console.warn(`[Campaign] Rejected: reason=TEST_TEMPLATE_IN_PRODUCTION`);
        return {
          success: false,
          error: {
            code: 'INVALID_PRODUCTION_TEMPLATE',
            message:
              "Test template 'hello_world' is not permitted for live production broadcasts. Please select an approved production template.",
          },
        };
      }

      // Production Safety Check 5: Template must be approved for production WABA
      if (!template || template.status !== 'approved') {
        console.warn(`[Campaign] Rejected: reason=TEMPLATE_NOT_APPROVED template=${templateName}`);
        return {
          success: false,
          error: {
            code: 'TEMPLATE_NOT_APPROVED',
            message: `Template '${templateName}' is not an approved production WhatsApp template.`,
          },
        };
      }

      effectiveMetaTemplateName = template.name;
      finalTemplateLanguage = template.language || finalTemplateLanguage;
      if (finalVariables.length === 0 && template.variables) {
        finalVariables = template.variables;
      }

      // Production Safety Check 6: Authoritative Server-Side Customer Opt-in Consent Verification
      const templateCat = (template.category || '').toUpperCase();
      const requiredConsentCategory: 'marketing' | 'utility' =
        templateCat === 'UTILITY' ? 'utility' : 'marketing';

      for (const r of recipients) {
        const norm = normalizeWhatsAppPhone(r.phone);
        if (!norm) continue;
        if (optedOutPhones.includes(norm) || normalizedOptedOut.has(norm)) continue;
        const hasConsent = await consentStore.hasActiveConsent(norm, requiredConsentCategory);
        if (hasConsent) {
          normalizedConsentedPhones.push(norm);
        }
      }

      // Deduplicate consented phones
      normalizedConsentedPhones = Array.from(new Set(normalizedConsentedPhones));

      if (normalizedConsentedPhones.length === 0) {
        console.warn(
          `[Campaign] Rejected: reason=NO_ELIGIBLE_CONSENTED_RECIPIENTS totalRecipients=${recipients.length} category=${requiredConsentCategory}`
        );
        return {
          success: false,
          error: {
            code: 'NO_ELIGIBLE_CONSENTED_RECIPIENTS',
            message:
              `No recipients with verified server-side WhatsApp opt-in consent found for ${requiredConsentCategory}. Production ${requiredConsentCategory} broadcasts require documented customer consent in the authoritative registry. Client-provided consent flags are not trusted.`,
          },
        };
      }

      targetCredentials = {
        phoneNumberId: env.PROD_WHATSAPP_PHONE_NUMBER_ID,
        accessToken: env.PROD_WHATSAPP_ACCESS_TOKEN,
      };
    } else {
      // --- DEVELOPER TEST MODE CHECKS ---

      // Test Mode Check 1: Enforce Test Mode Recipient Limit (default 5)
      if (recipients.length > env.TEST_RECIPIENT_LIMIT) {
        console.warn(`[Campaign] Rejected: reason=TEST_RECIPIENT_LIMIT`);
        return {
          success: false,
          error: {
            code: 'TEST_RECIPIENT_LIMIT',
            message: `WhatsApp Test Mode allows up to ${env.TEST_RECIPIENT_LIMIT} authorized recipients.`,
          },
        };
      }

      // Test Mode Check 2: Template validation
      if (template) {
        if (template.status !== 'approved') {
          console.warn(
            `[Campaign] Rejected: reason=TEMPLATE_NOT_APPROVED template='${template.displayName}' (${template.name}) status='${template.status}'`
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
        finalTemplateLanguage = template.language || finalTemplateLanguage;
        if (finalVariables.length === 0 && template.variables) {
          finalVariables = template.variables;
        }
      } else if (templateName !== 'hello_world') {
        console.warn(
          `[Campaign] Rejected: reason=TEMPLATE_NOT_FOUND template='${templateName}' has no mapping.`
        );
        return {
          success: false,
          error: {
            code: 'UNMAPPED_TEMPLATE',
            message: 'This GlowBlast template is not connected to an approved WhatsApp template yet.',
          },
        };
      }

      targetCredentials = {
        phoneNumberId: env.WHATSAPP_PHONE_NUMBER_ID,
        accessToken: env.WHATSAPP_ACCESS_TOKEN,
      };
    }

    const allowlist = mode === 'test' ? getAuthorizedTestRecipients() : [];

    console.log(
      `[Campaign] Initializing campaign ${effectiveCampaignId} ('${effectiveCampaignName}') [mode=${mode}] with ${recipients.length} recipients, Meta template='${effectiveMetaTemplateName}' (${finalTemplateLanguage})`
    );

    // Prepare stored messages
    const storedMessages: StoredMessage[] = [];
    const now = new Date().toISOString();
    let queuedCount = 0;
    let excludedOptOutCount = 0;

    for (let i = 0; i < recipients.length; i++) {
      const r = recipients[i];
      const localCustomerId = r.localCustomerId?.trim() || `cust_${i + 1}`;
      const customerName = r.name?.trim() || 'Valued Customer';
      const internalId = `${effectiveCampaignId}_${localCustomerId}`;
      const normalizedPhone = normalizeWhatsAppPhone(r.phone);

      const isOptedOut =
        !normalizedPhone ||
        optedOutPhones.includes(normalizedPhone) ||
        normalizedOptedOut.has(normalizedPhone);

      let initialStatus: StoredMessage['status'] = 'queued';
      if (isOptedOut) {
        initialStatus = 'excluded_opt_out';
        excludedOptOutCount++;
      } else {
        queuedCount++;
      }

      const msg: StoredMessage = {
        id: internalId,
        campaignId: effectiveCampaignId,
        localCustomerId,
        recipientName: customerName,
        normalizedPhone: normalizedPhone || r.phone,
        status: initialStatus,
        templateName: effectiveMetaTemplateName,
        templateLanguage: finalTemplateLanguage,
        createdAt: now,
        updatedAt: now,
      };

      storedMessages.push(msg);
    }

    // --- PHASE 4: ATOMIC SETUP TRANSACTION ---
    const pool = getPool();
    const client = await pool.connect();
    let isCreator = false;

    try {
      await client.query('BEGIN');

      // 1. Insert campaign with ON CONFLICT (client_request_token) DO NOTHING
      const insertRes = await client.query<{ campaign_id: string; status: string }>(
        `INSERT INTO campaigns (
           campaign_id, client_request_token, campaign_name, mode, status,
           template_name, template_language, total_recipients,
           count_queued, count_accepted, count_sent, count_delivered,
           count_read, count_failed, count_excluded_opt_out,
           created_at, updated_at
         )
         VALUES ($1, $2, $3, $4, 'processing', $5, $6, $7, $8, 0, 0, 0, 0, 0, $9, NOW(), NOW())
         ON CONFLICT (client_request_token) DO NOTHING
         RETURNING campaign_id, status;`,
        [
          effectiveCampaignId,
          clientRequestToken,
          effectiveCampaignName,
          mode,
          effectiveMetaTemplateName,
          finalTemplateLanguage,
          recipients.length,
          queuedCount,
          excludedOptOutCount,
        ]
      );

      if (insertRes.rows.length === 0) {
        // Token conflict! Roll back this transaction immediately
        await client.query('ROLLBACK');
        client.release();

        console.log(`[Campaign] Idempotent hit: client_request_token='${clientRequestToken}'`);
        // In a separate query, retrieve existing campaign
        let existingCamp = await campaignStore.getByClientRequestToken(clientRequestToken);
        if (!existingCamp) {
          for (let attempt = 0; attempt < 5; attempt++) {
            await new Promise((r) => setTimeout(r, 100));
            existingCamp = await campaignStore.getByClientRequestToken(clientRequestToken);
            if (existingCamp) break;
          }
        }

        if (existingCamp) {
          return {
            success: true,
            campaign: existingCamp,
          };
        }

        return {
          success: false,
          error: {
            code: 'DUPLICATE_CAMPAIGN',
            message: `Campaign with token '${clientRequestToken}' is already processed or being processed.`,
          },
        };
      }

      isCreator = true;

      // 2. Production quota check and reservation inside setup transaction
      if (mode === 'production') {
        await client.query(
          `SELECT lock_key FROM app_locks WHERE lock_key = 'production_quota_reservation' FOR UPDATE;`
        );

        const usageRes = await client.query<{ unique_count: string }>(
          `SELECT COUNT(DISTINCT normalized_phone) AS unique_count
           FROM recipient_reservations
           WHERE reserved_at >= NOW() - INTERVAL '24 hours';`
        );
        const currentCount = parseInt(usageRes.rows[0]?.unique_count || '0', 10);

        const newPhonesRes = await client.query<{ new_count: string }>(
          `SELECT COUNT(DISTINCT p) AS new_count
           FROM UNNEST($1::text[]) AS p
           WHERE p NOT IN (
             SELECT normalized_phone
             FROM recipient_reservations
             WHERE reserved_at >= NOW() - INTERVAL '24 hours'
           );`,
          [normalizedConsentedPhones]
        );
        const newCount = parseInt(newPhonesRes.rows[0]?.new_count || '0', 10);

        if (currentCount + newCount > env.PROD_UNIQUE_RECIPIENTS_PER_24H_LIMIT) {
          throw new Error(
            `DAILY_RECIPIENT_LIMIT_EXCEEDED: Rolling 24-hour limit of ${env.PROD_UNIQUE_RECIPIENTS_PER_24H_LIMIT} unique recipients reached.`
          );
        }

        for (const phone of normalizedConsentedPhones) {
          await client.query(
            `INSERT INTO recipient_reservations (campaign_id, normalized_phone, reserved_at)
             VALUES ($1, $2, NOW())
             ON CONFLICT (campaign_id, normalized_phone) DO NOTHING;`,
            [effectiveCampaignId, phone]
          );
        }
      }

      // 3. Insert eligible queued message records and excluded-recipient records
      for (const msg of storedMessages) {
        await client.query(
          `INSERT INTO campaign_messages (
             id, campaign_id, local_customer_id, recipient_name, normalized_phone,
             status, template_name, template_language, created_at, updated_at
           )
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW(), NOW())
           ON CONFLICT (id) DO NOTHING;`,
          [
            msg.id,
            msg.campaignId,
            msg.localCustomerId,
            msg.recipientName,
            msg.normalizedPhone,
            msg.status,
            msg.templateName,
            msg.templateLanguage,
          ]
        );
      }

      // 4. Set campaign counts to match records actually inserted
      await client.query(
        `UPDATE campaigns
         SET total_recipients = $2,
             count_queued = $3,
             count_excluded_opt_out = $4,
             updated_at = NOW()
         WHERE campaign_id = $1;`,
        [effectiveCampaignId, storedMessages.length, queuedCount, excludedOptOutCount]
      );

      // 5. Commit setup transaction
      await client.query('COMMIT');
    } catch (err: any) {
      await client.query('ROLLBACK');
      console.error(`[Campaign] Transaction rollback on setup: ${err.message}`);
      if (err.message && err.message.startsWith('DAILY_RECIPIENT_LIMIT_EXCEEDED')) {
        return {
          success: false,
          error: {
            code: 'DAILY_RECIPIENT_LIMIT_EXCEEDED',
            message: err.message,
          },
        };
      }
      return {
        success: false,
        error: {
          code: 'CAMPAIGN_SETUP_FAILED',
          message: err.message || 'Failed to initialize campaign transaction',
        },
      };
    } finally {
      try {
        client.release();
      } catch (_) {}
    }

    let createdCampaign: StoredCampaign | undefined;
    try {
      createdCampaign = await campaignStore.get(effectiveCampaignId);
    } catch (err: any) {
      console.error(`[Campaign] Safe fallback: Error retrieving created campaign ${effectiveCampaignId}: ${err.message}`);
      createdCampaign = {
        campaignId: effectiveCampaignId,
        clientRequestToken,
        campaignName: effectiveCampaignName,
        status: 'processing',
        templateName: effectiveMetaTemplateName,
        templateLanguage: finalTemplateLanguage,
        total: recipients.length,
        queued: queuedCount,
        accepted: 0,
        sent: 0,
        delivered: 0,
        read: 0,
        replied: 0,
        failed: 0,
        excludedOptOut: excludedOptOutCount,
        messages: storedMessages,
        createdAt: now,
        updatedAt: now,
      };
    }

    // Only the creator that successfully committed the setup initiates background dispatch
    if (isCreator && queuedCount > 0) {
      setImmediate(() => {
        this.executeCampaignSend({
          campaignId: effectiveCampaignId,
          templateName: effectiveMetaTemplateName,
          templateLanguage: finalTemplateLanguage,
          variables: finalVariables,
          businessName: effectiveBusinessName,
          allowlist,
          optedOutSet: normalizedOptedOut,
          templateComponents,
          templateRef: template,
          credentials: targetCredentials,
          mode,
          messages: storedMessages.filter((m) => m.status === 'queued'),
        });
      });
    }

    return {
      success: true,
      campaign: createdCampaign,
    };
  }

  /**
   * Executes controlled sequential sending for the campaign with atomic queued message claiming.
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
    credentials: WhatsAppCredentials;
    mode: 'test' | 'production';
    messages: StoredMessage[];
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
      credentials,
      mode,
      messages,
    } = params;

    console.log(
      `[Campaign] Starting dispatch loop for ${campaignId} [mode=${mode}] using template '${templateName}'`
    );

    for (const rawMsg of messages) {
      // Atomic claim: only proceed if this worker successfully claims the queued message
      const claimed = await messageStore.claimQueuedMessage(rawMsg.id);
      if (!claimed) {
        console.log(`[Campaign] Message ${rawMsg.id} already claimed or transitioned. Skipping.`);
        continue;
      }

      // Check 1: Valid normalized phone
      if (!claimed.normalizedPhone || claimed.normalizedPhone.length < 10) {
        console.warn(`[Campaign] Invalid phone for ${claimed.recipientName}`);
        await messageStore.updateStatus(claimed.id, 'failed', undefined, {
          code: 400,
          title: 'Invalid Phone Number',
          message: 'Phone number could not be normalized for WhatsApp.',
        });
        realtimeService.broadcastMessageStatus({
          campaignId,
          phone: claimed.normalizedPhone,
          status: 'failed',
          errorCode: 400,
          errorTitle: 'Invalid Phone Number',
        });
        continue;
      }

      // Check 2: Defensive Opt-Out check
      if (optedOutSet.has(claimed.normalizedPhone)) {
        console.log(`[Campaign] Skipping ${maskPhone(claimed.normalizedPhone)}: Customer is opted out`);
        await messageStore.updateStatus(claimed.id, 'excluded_opt_out', undefined, {
          title: 'Opted-Out',
          message: 'Customer is on the opt-out suppression list.',
        });
        realtimeService.broadcastMessageStatus({
          campaignId,
          phone: claimed.normalizedPhone,
          status: 'excluded_opt_out',
        });
        continue;
      }

      // Check 3: Authoritative Production Opt-in Consent check
      if (mode === 'production') {
        const requiredConsentCategory: 'marketing' | 'utility' =
          (templateRef?.category || '').toUpperCase() === 'UTILITY' ? 'utility' : 'marketing';
        const hasServerConsent = await consentStore.hasActiveConsent(claimed.normalizedPhone, requiredConsentCategory);
        if (!hasServerConsent) {
          console.warn(
            `[Campaign] Skipping ${maskPhone(claimed.normalizedPhone)}: Missing verified server-side ${requiredConsentCategory} opt-in consent`
          );
          await messageStore.updateStatus(claimed.id, 'failed', undefined, {
            code: 403,
            title: 'Missing Opt-in Consent',
            message: `Recipient lacks verified server-side ${requiredConsentCategory} opt-in consent in the authoritative registry.`,
          });
          realtimeService.broadcastMessageStatus({
            campaignId,
            phone: claimed.normalizedPhone,
            status: 'failed',
            errorCode: 403,
            errorTitle: 'Missing Opt-in Consent',
          });
          continue;
        }
      }

      // Check 4: Test mode allowlist check
      if (mode === 'test' && allowlist.length > 0 && !allowlist.includes(claimed.normalizedPhone)) {
        const masked = maskPhone(claimed.normalizedPhone);
        console.warn(`[Campaign] Recipient ${masked} not in authorized test allowlist`);
        await messageStore.updateStatus(claimed.id, 'failed', undefined, {
          code: 403,
          title: 'Unauthorized Test Recipient',
          message: `Recipient ${masked} is not in the authorized Meta test allowlist. Add this number in Meta App Dashboard > WhatsApp > API Setup > To.`,
          details: 'Recipient is not authorized for the current Meta WhatsApp test environment.',
        });
        realtimeService.broadcastMessageStatus({
          campaignId,
          phone: claimed.normalizedPhone,
          status: 'failed',
          errorCode: 403,
          errorTitle: 'Unauthorized Test Recipient',
        });
        continue;
      }

      // Construct recipient-specific components
      let resolvedComponents = templateComponents;

      if (templateName === 'hello_world') {
        resolvedComponents = undefined;
      } else if (!resolvedComponents && variables.length > 0) {
        const bodyParameters = variables.map((v) => {
          const vLower = v.toLowerCase();
          let textVal = '';
          if (vLower === 'name' || vLower === 'customer_name' || vLower === 'client') {
            textVal = claimed.recipientName || 'Client';
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

      // Call Meta WhatsApp Cloud API outside of any database transaction
      const result = await WhatsAppService.sendTemplateMessage({
        recipientPhone: claimed.normalizedPhone,
        recipientName: claimed.recipientName,
        templateName,
        templateLanguage,
        templateComponents: resolvedComponents,
        bizOpaqueCallbackData: claimed.id,
        credentials,
      });

      if (result.success && result.providerMessageId) {
        await messageStore.updateStatus(claimed.id, 'accepted', result.providerMessageId);
        realtimeService.broadcastMessageStatus({
          campaignId,
          phone: claimed.normalizedPhone,
          status: 'accepted',
          providerMessageId: result.providerMessageId,
        });
      } else if (result.isAmbiguousTimeout) {
        console.warn(`[Campaign] Message ${claimed.id} timed out. Transitioning to uncertain_timeout.`);
        await messageStore.updateStatus(claimed.id, 'uncertain_timeout', undefined, {
          code: 504,
          title: 'Ambiguous Network Timeout',
          message: 'The network request to Meta timed out. Awaiting webhook reconciliation or manual review.',
        });
        realtimeService.broadcastMessageStatus({
          campaignId,
          phone: claimed.normalizedPhone,
          status: 'uncertain_timeout',
          errorCode: 504,
          errorTitle: 'Ambiguous Network Timeout',
        });
      } else {
        await messageStore.updateStatus(claimed.id, 'failed', undefined, {
          code: result.errorCode,
          title: result.errorTitle,
          message: result.errorMessage,
          details: result.errorDetails,
        });
        realtimeService.broadcastMessageStatus({
          campaignId,
          phone: claimed.normalizedPhone,
          status: 'failed',
          errorCode: result.errorCode,
          errorTitle: result.errorTitle,
        });

        if (result.errorCode === 131031) {
          console.error(`[Campaign] Account locked/restricted (Error 131031). Aborting remaining dispatch.`);
          break;
        }
      }

      // Controlled delay between sends (500ms) to respect rate limits
      await new Promise((resolve) => setTimeout(resolve, 500));
    }

    try {
      const finalSummary = await campaignStore.recalculateAndSaveCampaignStatus(campaignId);
      realtimeService.broadcastCampaignProgress(campaignId);
      console.log(
        `[Campaign] Completed dispatch loop for ${campaignId}. Authoritative status: ${finalSummary?.status}`
      );
    } catch (err: any) {
      console.error(`[Campaign] Error finalizing campaign status for ${campaignId}: ${err?.message || err}`);
    }
  }
}
