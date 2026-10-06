import { env } from '../config/env';
import { maskPhone } from '../utils/phone';
import { MetaSendMessageResponse, MetaApiError } from '../types/whatsapp';

export interface WhatsAppSendResult {
  success: boolean;
  providerMessageId?: string;
  status: 'accepted' | 'failed';
  httpStatus?: number;
  errorCode?: number;
  errorTitle?: string;
  errorMessage?: string;
  errorDetails?: string;
  requestedTemplateName?: string;
  requestedTemplateLanguage?: string;
}

export class WhatsAppService {
  /**
   * Validates if Meta credentials are fully configured.
   */
  public static validateConfiguration(): { valid: boolean; reason?: string } {
    if (!env.WHATSAPP_PHONE_NUMBER_ID) {
      return { valid: false, reason: 'WHATSAPP_PHONE_NUMBER_ID is not configured in backend environment.' };
    }
    if (!env.WHATSAPP_ACCESS_TOKEN) {
      return { valid: false, reason: 'WHATSAPP_ACCESS_TOKEN is not configured in backend environment.' };
    }
    return { valid: true };
  }

  /**
   * Sends an official WhatsApp Template message using Meta Cloud API.
   * By default uses 'hello_world' (en_US) test template provided with Meta test numbers.
   */
  public static async sendTemplateMessage(params: {
    recipientPhone: string;
    recipientName?: string;
    templateName: string;
    templateLanguage?: string;
    templateComponents?: Array<{
      type: string;
      parameters: Array<{
        type: string;
        text?: string;
        [key: string]: any;
      }>;
    }>;
  }): Promise<WhatsAppSendResult> {
    const configCheck = this.validateConfiguration();
    if (!configCheck.valid) {
      console.warn(`[WhatsApp] Configuration missing: ${configCheck.reason}`);
      return {
        success: false,
        status: 'failed',
        httpStatus: 401,
        errorCode: 401,
        errorTitle: 'Configuration Missing',
        errorMessage: configCheck.reason,
      };
    }

    const {
      recipientPhone,
      recipientName,
      templateName,
      templateLanguage = 'en_US',
      templateComponents,
    } = params;

    if (!templateName || templateName.trim().length === 0) {
      return {
        success: false,
        status: 'failed',
        httpStatus: 400,
        errorCode: 400,
        errorTitle: 'Missing Template',
        errorMessage: 'A valid WhatsApp template name must be provided.',
      };
    }

    const masked = maskPhone(recipientPhone);
    console.log(
      `[WhatsApp] Template selected:\nname=${templateName}\nlanguage=${templateLanguage}\nrecipient=${masked}`
    );

    const url = `https://graph.facebook.com/${env.WHATSAPP_API_VERSION}/${env.WHATSAPP_PHONE_NUMBER_ID}/messages`;

    const payload: Record<string, any> = {
      messaging_product: 'whatsapp',
      recipient_type: 'individual',
      to: recipientPhone,
      type: 'template',
      template: {
        name: templateName,
        language: {
          code: templateLanguage,
        },
      },
    };

    if (templateComponents && templateComponents.length > 0) {
      payload.template.components = templateComponents;
    }

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${env.WHATSAPP_ACCESS_TOKEN}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload),
      });

      const data = (await response.json()) as any;

      if (!response.ok) {
        const error: MetaApiError = data?.error || {
          message: `HTTP ${response.status} from Meta API`,
          code: response.status,
          type: 'OAuthException',
        };

        const errorDetails = error.error_data?.details || error.message;

        console.error(
          `[Meta Error] httpStatus=${response.status} code=${error.code} type=${error.type} message=${error.message} details=${errorDetails}`
        );

        let friendlyTitle = error.type || 'Meta API Error';
        let friendlyMessage = error.message || 'Failed to send WhatsApp message via Meta Cloud API';

        if (error.code === 131030) {
          friendlyTitle = 'Unauthorized Test Recipient';
          friendlyMessage =
            'Recipient phone number is not authorized in Meta developer test mode. Add this number in Meta App Dashboard > WhatsApp > API Setup > To.';
        } else if (error.code === 131031) {
          friendlyTitle = 'Business Account Locked';
          friendlyMessage = 'WhatsApp Business Account is restricted. Meta rejected this message.';
        } else if (error.code === 131047) {
          friendlyTitle = 'Re-engagement Window Expired';
          friendlyMessage =
            'Cannot send free-form message outside 24-hour customer window. Approved WhatsApp template is required.';
        } else if (error.code === 132000) {
          friendlyTitle = 'Template Not Found';
          friendlyMessage = `Template '${templateName}' does not exist in language '${templateLanguage}' on your Meta WhatsApp Business Account (Error 132000: ${error.message}). Please verify the exact template name and language in Meta WhatsApp Manager.`;
        } else if (error.code === 132001) {
          friendlyTitle = 'Template Translation Missing / Not Found';
          friendlyMessage = `Template '${templateName}' does not exist in language '${templateLanguage}' on your Meta WhatsApp Business Account (Error 132001: ${error.message}). Please verify the exact template name and language code in Meta WhatsApp Manager.`;
        } else if (error.code === 132005) {
          friendlyTitle = 'Invalid Template Parameters';
          friendlyMessage = `The parameter count or format does not match the approved template definition for '${templateName}'.`;
        } else if (error.code === 132007) {
          friendlyTitle = 'Template Paused';
          friendlyMessage = `Template '${templateName}' has been paused by Meta due to low quality rating.`;
        } else if (error.code === 190) {
          friendlyTitle = 'Invalid Access Token';
          friendlyMessage =
            'Meta access token is expired or invalid. Please refresh WHATSAPP_ACCESS_TOKEN in backend environment.';
        } else if (error.code === 80007 || error.code === 130429) {
          friendlyTitle = 'Rate Limit Exceeded';
          friendlyMessage = 'WhatsApp Cloud API throughput limit exceeded. Please retry in a few moments.';
        }

        return {
          success: false,
          status: 'failed',
          httpStatus: response.status,
          errorCode: error.code,
          errorTitle: friendlyTitle,
          errorMessage: friendlyMessage,
          errorDetails,
          requestedTemplateName: templateName,
          requestedTemplateLanguage: templateLanguage,
        };
      }

      const metaRes = data as MetaSendMessageResponse;
      const providerId = metaRes.messages?.[0]?.id;

      if (!providerId) {
        console.warn(`[Meta Warning] HTTP 200 returned but no provider message ID in response:`, data);
        return {
          success: false,
          status: 'failed',
          httpStatus: response.status,
          errorCode: 500,
          errorTitle: 'Meta Response Missing ID',
          errorMessage: 'Meta accepted the request but did not return a WhatsApp message ID.',
        };
      }

      console.log(`[Meta Response] httpStatus=${response.status} providerMessageId=${providerId}`);

      return {
        success: true,
        providerMessageId: providerId,
        status: 'accepted',
        httpStatus: response.status,
      };
    } catch (err: any) {
      console.error(`[WhatsApp Error] Network error connecting to Meta Cloud API: ${err.message}`);
      return {
        success: false,
        status: 'failed',
        httpStatus: 503,
        errorCode: 503,
        errorTitle: 'Network Error',
        errorMessage: `Could not reach Meta WhatsApp Cloud API: ${err.message}`,
        errorDetails: err.stack,
      };
    }
  }
}

