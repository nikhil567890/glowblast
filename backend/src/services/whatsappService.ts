import { env } from '../config/env';
import { maskPhone } from '../utils/phone';
import { MetaSendMessageResponse, MetaApiError } from '../types/whatsapp';

export interface WhatsAppSendResult {
  success: boolean;
  providerMessageId?: string;
  status: 'accepted' | 'failed';
  errorCode?: number;
  errorTitle?: string;
  errorMessage?: string;
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
    templateName?: string;
    templateLanguage?: string;
  }): Promise<WhatsAppSendResult> {
    const configCheck = this.validateConfiguration();
    if (!configCheck.valid) {
      console.warn(`[WhatsApp] Configuration missing: ${configCheck.reason}`);
      return {
        success: false,
        status: 'failed',
        errorCode: 401,
        errorTitle: 'Configuration Missing',
        errorMessage: configCheck.reason,
      };
    }

    const { recipientPhone, templateName = 'hello_world', templateLanguage = 'en_US' } = params;

    const masked = maskPhone(recipientPhone);
    console.log(`[WhatsApp] Sending template '${templateName}' to ${masked} via Meta Cloud API (${env.WHATSAPP_API_VERSION})`);

    const url = `https://graph.facebook.com/${env.WHATSAPP_API_VERSION}/${env.WHATSAPP_PHONE_NUMBER_ID}/messages`;

    const payload = {
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

        console.error(`[WhatsApp] Meta rejected request. Code: ${error.code}. Type: ${error.type}. Message: ${error.message}`);

        // Specific handling for Error 131031 (Business Account locked) - DO NOT RETRY
        if (error.code === 131031) {
          return {
            success: false,
            status: 'failed',
            errorCode: 131031,
            errorTitle: 'Business Account locked',
            errorMessage: 'WhatsApp Business Account is restricted. Meta rejected this message.',
          };
        }

        return {
          success: false,
          status: 'failed',
          errorCode: error.code,
          errorTitle: error.type || 'Meta API Error',
          errorMessage: error.message || 'Failed to send WhatsApp message via Meta Cloud API',
        };
      }

      const metaRes = data as MetaSendMessageResponse;
      const providerId = metaRes.messages?.[0]?.id || `wamid_${Date.now()}`;

      console.log(`[WhatsApp] Meta accepted request. Provider Message ID: ${providerId}`);

      return {
        success: true,
        providerMessageId: providerId,
        status: 'accepted',
      };
    } catch (err: any) {
      console.error(`[WhatsApp] Network or unexpected error connecting to Meta Cloud API: ${err.message}`);
      return {
        success: false,
        status: 'failed',
        errorCode: 503,
        errorTitle: 'Network Error',
        errorMessage: `Could not reach Meta WhatsApp Cloud API: ${err.message}`,
      };
    }
  }
}
