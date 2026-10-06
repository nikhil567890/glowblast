import { env } from '../config/env';
import { templateStore } from '../store/templateStore';
import {
  WhatsAppTemplate,
  CreateTemplateInput,
  TemplateApprovalStatus,
  MetaTemplateStatus,
} from '../types/template';

export interface MetaTemplateSyncResult {
  success: boolean;
  syncedCount: number;
  templates: WhatsAppTemplate[];
  error?: {
    code?: number;
    type?: string;
    message: string;
    subcode?: number;
    fbtraceId?: string;
  };
}

export class TemplateService {
  /**
   * Returns all templates from store.
   */
  public static listTemplates(): WhatsAppTemplate[] {
    return templateStore.getAll();
  }

  /**
   * Retrieves a single template by ID or Meta name.
   */
  public static getTemplate(idOrName: string): WhatsAppTemplate | undefined {
    return templateStore.findByIdOrName(idOrName);
  }

  /**
   * Extracts variable keys from local body string (e.g. "Hi {name} at {business_name}").
   */
  public static extractVariables(body: string): string[] {
    const matches = body.match(/\{([a-zA-Z0-9_]+)\}/g);
    if (!matches) return [];
    const unique = new Set<string>();
    for (const m of matches) {
      unique.add(m.replace('{', '').replace('}', ''));
    }
    return Array.from(unique);
  }

  /**
   * Converts local variable syntax `{var}` to Meta numbered syntax `{{1}}`, `{{2}}`.
   */
  public static convertToMetaBody(
    body: string,
    variables: string[]
  ): { metaBody: string; mapping: Record<string, string> } {
    let metaBody = body;
    const mapping: Record<string, string> = {};

    variables.forEach((v, idx) => {
      const metaPlaceholder = `{{${idx + 1}}}`;
      mapping[v] = metaPlaceholder;
      metaBody = metaBody.replace(new RegExp(`\\{${v}\\}`, 'g'), metaPlaceholder);
    });

    return { metaBody, mapping };
  }

  public static convertToMetaNumberedBody(body: string, variables: string[]): string {
    return this.convertToMetaBody(body, variables).metaBody;
  }

  public static getParameterMapping(variables: string[]): Record<string, string> {
    return this.convertToMetaBody('', variables).mapping;
  }

  public static validateTemplateParameters(
    tpl: WhatsAppTemplate,
    parameters: Record<string, string>
  ): { isValid: boolean; missingVariables: string[] } {
    const missing: string[] = [];
    for (const v of tpl.variables) {
      if (!parameters[v] || parameters[v].trim().length === 0) {
        missing.push(v);
      }
    }
    return {
      isValid: missing.length === 0,
      missingVariables: missing,
    };
  }

  public static resolvePreview(
    tpl: WhatsAppTemplate,
    parameters: Record<string, string>
  ): string {
    let resolved = tpl.body;
    for (const [key, value] of Object.entries(parameters)) {
      resolved = resolved.replace(new RegExp(`\\{${key}\\}`, 'g'), value);
    }
    return resolved;
  }

  /**
   * Creates a new GlowBlast WhatsApp template and optionally submits it to Meta.
   */
  public static async createTemplate(input: CreateTemplateInput): Promise<{
    success: boolean;
    template: WhatsAppTemplate;
    metaError?: {
      code?: number;
      type?: string;
      message: string;
      subcode?: number;
    };
  }> {
    const cleanName = input.name.trim().toLowerCase();
    const variables =
      input.variables && input.variables.length > 0
        ? input.variables
        : this.extractVariables(input.body);

    const now = new Date().toISOString();
    const id = `tpl_${cleanName}`;

    let status: TemplateApprovalStatus = 'draft';
    let metaStatus: MetaTemplateStatus = 'NOT_SUBMITTED';
    let metaTemplateId: string | undefined;
    let metaError: any = undefined;

    // Check if user requested programmatic submission to Meta
    if (input.submitToMeta && env.WHATSAPP_BUSINESS_ACCOUNT_ID && env.WHATSAPP_ACCESS_TOKEN) {
      const { metaBody } = this.convertToMetaBody(input.body, variables);

      const exampleValuesList = variables.map(
        (v) => input.exampleValues?.[v] || (v === 'name' ? 'Client' : 'Wellness Center')
      );

      const metaPayload: Record<string, any> = {
        name: cleanName,
        category: input.category,
        language: input.language || 'en_US',
        components: [
          {
            type: 'BODY',
            text: metaBody,
            ...(exampleValuesList.length > 0
              ? {
                  example: {
                    body_text: [exampleValuesList],
                  },
                }
              : {}),
          },
        ],
      };

      try {
        const url = `https://graph.facebook.com/${env.WHATSAPP_API_VERSION}/${env.WHATSAPP_BUSINESS_ACCOUNT_ID}/message_templates`;
        console.log(`[TemplateService] Submitting template '${cleanName}' to Meta WhatsApp API`);

        const response = await fetch(url, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${env.WHATSAPP_ACCESS_TOKEN}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(metaPayload),
        });

        const data = (await response.json()) as any;

        if (response.ok && data.id) {
          metaTemplateId = data.id;
          status = data.status === 'APPROVED' ? 'approved' : 'pending_approval';
          metaStatus = (data.status as MetaTemplateStatus) || 'PENDING';
          console.log(
            `[TemplateService] Meta accepted template submission: ID=${metaTemplateId}, status=${metaStatus}`
          );
        } else {
          const err = data.error || {};
          metaError = {
            code: err.code || response.status,
            type: err.type || 'OAuthException',
            message: err.message || 'Failed to submit template to Meta',
            subcode: err.error_subcode,
          };
          console.warn(`[TemplateService] Meta submission error:`, metaError);
          // Keep as draft so user can review and retry
          status = 'draft';
          metaStatus = 'NOT_SUBMITTED';
        }
      } catch (e: any) {
        metaError = {
          message: `Network error connecting to Meta API: ${e.message}`,
        };
        status = 'draft';
        metaStatus = 'NOT_SUBMITTED';
      }
    }

    const tpl: WhatsAppTemplate = {
      id,
      name: cleanName,
      displayName: input.displayName.trim(),
      description: input.description,
      category: input.category,
      language: input.language || 'en_US',
      status,
      metaStatus,
      metaTemplateId,
      body: input.body,
      variables,
      exampleValues: input.exampleValues,
      createdAt: now,
      updatedAt: now,
    };

    templateStore.create(tpl);

    return {
      success: true,
      template: tpl,
      metaError,
    };
  }

  /**
   * Synchronizes templates from official Meta WhatsApp Business Platform.
   */
  public static async syncFromMeta(): Promise<MetaTemplateSyncResult> {
    if (!env.WHATSAPP_BUSINESS_ACCOUNT_ID || !env.WHATSAPP_ACCESS_TOKEN) {
      return {
        success: false,
        syncedCount: 0,
        templates: templateStore.getAll(),
        error: {
          message:
            'Meta WhatsApp Business credentials (WHATSAPP_BUSINESS_ACCOUNT_ID / WHATSAPP_ACCESS_TOKEN) are not configured.',
        },
      };
    }

    const url = `https://graph.facebook.com/${env.WHATSAPP_API_VERSION}/${env.WHATSAPP_BUSINESS_ACCOUNT_ID}/message_templates?limit=100`;

    try {
      console.log(`[TemplateService] Fetching templates from Meta: WABA=${env.WHATSAPP_BUSINESS_ACCOUNT_ID}`);
      const response = await fetch(url, {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${env.WHATSAPP_ACCESS_TOKEN}`,
        },
      });

      const data = (await response.json()) as any;

      if (!response.ok || data.error) {
        const err = data.error || {};
        console.warn(`[TemplateService] Meta API sync returned error:`, err);
        return {
          success: false,
          syncedCount: 0,
          templates: templateStore.getAll(),
          error: {
            code: err.code || response.status,
            type: err.type || 'OAuthException',
            message: err.message || 'Error communicating with Meta WhatsApp Cloud API',
            subcode: err.error_subcode,
            fbtraceId: err.fbtrace_id,
          },
        };
      }

      const metaTemplates: any[] = data.data || [];
      let syncedCount = 0;
      const now = new Date().toISOString();

      for (const mt of metaTemplates) {
        const metaName: string = mt.name;
        const metaStatus: MetaTemplateStatus = mt.status || 'APPROVED';
        const metaCategory = mt.category || 'MARKETING';
        const metaLang = mt.language || 'en_US';
        const metaId = mt.id;

        // Map Meta status to GlowBlast status
        let localStatus: TemplateApprovalStatus = 'pending_approval';
        if (metaStatus === 'APPROVED') {
          localStatus = 'approved';
        } else if (metaStatus === 'REJECTED') {
          localStatus = 'rejected';
        } else if (metaStatus === 'PAUSED' || metaStatus === 'DISABLED') {
          localStatus = 'disabled';
        }

        const existing = templateStore.getByName(metaName);
        if (existing) {
          templateStore.update(existing.id, {
            status: localStatus,
            metaStatus,
            metaTemplateId: metaId,
            language: metaLang,
            lastSyncedAt: now,
          });
          syncedCount++;
        } else {
          // Extract body text from components if available
          let bodyText = `Meta Template: ${metaName}`;
          if (mt.components && Array.isArray(mt.components)) {
            const bodyComp = mt.components.find((c: any) => c.type === 'BODY');
            if (bodyComp && bodyComp.text) {
              bodyText = bodyComp.text;
            }
          }

          const newTpl: WhatsAppTemplate = {
            id: `tpl_${metaName}`,
            name: metaName,
            displayName: metaName
              .split('_')
              .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
              .join(' '),
            description: `Imported from Meta WhatsApp Business Platform (${metaStatus})`,
            category: metaCategory,
            language: metaLang,
            status: localStatus,
            metaStatus,
            metaTemplateId: metaId,
            body: bodyText,
            variables: this.extractVariables(bodyText),
            createdAt: now,
            updatedAt: now,
            lastSyncedAt: now,
          };
          templateStore.create(newTpl);
          syncedCount++;
        }
      }

      console.log(`[TemplateService] Successfully synced ${syncedCount} templates from Meta`);
      return {
        success: true,
        syncedCount,
        templates: templateStore.getAll(),
      };
    } catch (e: any) {
      console.error(`[TemplateService] Network error during Meta sync:`, e.message);
      return {
        success: false,
        syncedCount: 0,
        templates: templateStore.getAll(),
        error: {
          message: `Network error connecting to Meta WhatsApp Cloud API: ${e.message}`,
        },
      };
    }
  }

  /**
   * Sets the approval status of a template (e.g. admin sync or confirmation).
   */
  public static updateStatus(
    id: string,
    status: TemplateApprovalStatus,
    metaStatus?: MetaTemplateStatus
  ): WhatsAppTemplate | undefined {
    return templateStore.updateStatus(id, status, metaStatus);
  }

  /**
   * Deletes a template.
   */
  public static deleteTemplate(id: string): boolean {
    return templateStore.delete(id);
  }
}
