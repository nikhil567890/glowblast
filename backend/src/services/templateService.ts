import { env } from '../config/env';
import { templateStore } from '../store/templateStore';
import { INITIAL_BUSINESS_ID } from '../middleware/authMiddleware';
import { resolveBusinessWhatsAppCredentials } from './credentialResolver';
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
   * Returns templates from store optionally filtered by mode.
   */
  public static async listTemplates(mode?: 'test' | 'production', businessId?: string): Promise<WhatsAppTemplate[]> {
    return templateStore.getAll(mode, businessId);
  }

  /**
   * Retrieves a single template by ID or Meta name.
   */
  public static async getTemplate(idOrName: string, mode?: 'test' | 'production', businessId?: string): Promise<WhatsAppTemplate | undefined> {
    return templateStore.findByIdOrName(idOrName, mode, undefined, businessId);
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
  public static async createTemplate(input: CreateTemplateInput, businessId?: string): Promise<{
    success: boolean;
    template: WhatsAppTemplate;
    metaError?: {
      code?: number;
      type?: string;
      message: string;
      subcode?: number;
    };
  }> {
    const effectiveBizId = businessId || input.businessId;
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
    if (input.submitToMeta) {
      if (!effectiveBizId) {
        throw new Error('Business ID is required to submit a template to Meta WhatsApp API');
      }
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
        const creds = await resolveBusinessWhatsAppCredentials(effectiveBizId, 'test');
        const url = `https://graph.facebook.com/${env.WHATSAPP_API_VERSION}/${creds.wabaId}/message_templates`;
        console.log(`[TemplateService] Submitting template '${cleanName}' to Meta WhatsApp API (WABA: ${creds.wabaId})`);

        const response = await fetch(url, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${creds.accessToken}`,
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
          code: e.httpStatus || 400,
          type: 'ConfigurationError',
          message: e.message || `Error submitting template to Meta: ${e.message}`,
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
      businessId: effectiveBizId,
      createdAt: now,
      updatedAt: now,
    };

    await templateStore.create(tpl, effectiveBizId);

    return {
      success: true,
      template: tpl,
      metaError,
    };
  }

  /**
   * Synchronizes templates from official Meta WhatsApp Business Platform for a specific business.
   */
  public static async syncFromMeta(
    mode: 'test' | 'production' = 'test',
    businessId?: string
  ): Promise<MetaTemplateSyncResult> {
    const isProd = mode === 'production';
    const effectiveBizId = businessId || INITIAL_BUSINESS_ID;

    let targetWabaId: string;
    let targetToken: string;
    try {
      const creds = await resolveBusinessWhatsAppCredentials(effectiveBizId, mode);
      targetWabaId = creds.wabaId;
      targetToken = creds.accessToken;
    } catch (credErr: any) {
      const modeLabel = isProd ? 'Production' : 'Test Sandbox';
      return {
        success: false,
        syncedCount: 0,
        templates: await templateStore.getAll(mode, effectiveBizId),
        error: {
          code: credErr.httpStatus || 403,
          message: credErr.message || `Meta WhatsApp credentials for ${modeLabel} mode are not configured for this business.`,
        },
      };
    }

    try {
      console.log(`[TemplateService] Fetching templates from Meta: business=${effectiveBizId} mode=${mode} WABA=${targetWabaId}`);
      
      let nextUrl: string | null = `https://graph.facebook.com/${env.WHATSAPP_API_VERSION}/${targetWabaId}/message_templates?limit=100`;
      const allMetaTemplates: any[] = [];
      let pageCount = 0;
      const MAX_PAGES = 25; // Safety cap to avoid runaway loops

      while (nextUrl && pageCount < MAX_PAGES) {
        pageCount++;
        const response = await fetch(nextUrl, {
          method: 'GET',
          headers: {
            Authorization: `Bearer ${targetToken}`,
          },
        });

        const data = (await response.json()) as any;

        if (!response.ok || data.error) {
          const err = data.error || {};
          console.warn(`[TemplateService] Meta API sync returned error:`, err);
          return {
            success: false,
            syncedCount: 0,
            templates: await templateStore.getAll(mode, effectiveBizId),
            error: {
              code: err.code || response.status,
              type: err.type || 'OAuthException',
              message: err.message || 'Error communicating with Meta WhatsApp Cloud API',
              subcode: err.error_subcode,
              fbtraceId: err.fbtrace_id,
            },
          };
        }

        if (Array.isArray(data.data)) {
          allMetaTemplates.push(...data.data);
        }

        // Advance to next page if cursor exists
        nextUrl = data.paging?.next || null;
      }

      let syncedCount = 0;
      const now = new Date().toISOString();

      for (const mt of allMetaTemplates) {
        const metaName: string = mt.name;
        const metaStatus: MetaTemplateStatus = mt.status || 'APPROVED';
        const metaCategory = (mt.category || 'MARKETING').toUpperCase() as any;
        // Keep exact language code returned by Meta (e.g. 'en', 'en_US', 'hi')
        const metaLang: string = (mt.language || 'en').trim();
        const metaId: string | undefined = mt.id ? String(mt.id) : undefined;

        // Map Meta status to GlowBlast status
        let localStatus: TemplateApprovalStatus = 'pending_approval';
        if (metaStatus === 'APPROVED') {
          localStatus = 'approved';
        } else if (metaStatus === 'REJECTED') {
          localStatus = 'rejected';
        } else if (metaStatus === 'PAUSED' || metaStatus === 'DISABLED') {
          localStatus = 'disabled';
        }

        // Extract body text from components if available
        let bodyText = `Meta Template: ${metaName}`;
        if (mt.components && Array.isArray(mt.components)) {
          const bodyComp = mt.components.find((c: any) => c.type?.toUpperCase() === 'BODY');
          if (bodyComp && bodyComp.text) {
            bodyText = bodyComp.text;
          }
        }
        const variables = this.extractVariables(bodyText);

        const displayName = metaName
          .split('_')
          .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
          .join(' ');

        // Check if matching template already exists for this business (matching name, mode, and language)
        const existing = await templateStore.findByIdOrName(metaName, mode, metaLang, effectiveBizId);

        if (existing) {
          await templateStore.update(existing.id, {
            name: metaName,
            displayName: existing.displayName || displayName,
            category: metaCategory,
            language: metaLang,
            status: localStatus,
            metaStatus,
            metaTemplateId: metaId,
            body: bodyText,
            variables,
            wabaId: targetWabaId,
            mode,
            businessId: effectiveBizId,
            lastSyncedAt: now,
          }, effectiveBizId);
          syncedCount++;
        } else {
          const templateIdPrefix = isProd ? 'tpl_prod_' : 'tpl_';
          const cleanLang = metaLang.toLowerCase().replace(/[^a-z0-9]/g, '_');
          const newTpl: WhatsAppTemplate = {
            id: `${templateIdPrefix}${metaName}_${cleanLang}`,
            name: metaName,
            displayName,
            description: `Imported from Meta WhatsApp Business Platform (${metaStatus} - ${mode} WABA)`,
            category: metaCategory,
            language: metaLang,
            status: localStatus,
            metaStatus,
            metaTemplateId: metaId,
            body: bodyText,
            variables,
            wabaId: targetWabaId,
            mode,
            businessId: effectiveBizId,
            createdAt: now,
            updatedAt: now,
            lastSyncedAt: now,
          };
          await templateStore.create(newTpl, effectiveBizId);
          syncedCount++;
        }
      }

      console.log(`[TemplateService] Successfully synced ${syncedCount} templates from Meta (${mode}) for business ${effectiveBizId} across ${pageCount} page(s)`);
      return {
        success: true,
        syncedCount,
        templates: await templateStore.getAll(mode, effectiveBizId),
      };
    } catch (e: any) {
      console.error(`[TemplateService] Network error during Meta sync:`, e.message);
      return {
        success: false,
        syncedCount: 0,
        templates: await templateStore.getAll(mode, effectiveBizId),
        error: {
          message: `Network error connecting to Meta WhatsApp Cloud API: ${e.message}`,
        },
      };
    }
  }

  /**
   * Sets the approval status of a template (e.g. admin sync or confirmation).
   */
  public static async updateStatus(
    id: string,
    status: TemplateApprovalStatus,
    metaStatus?: MetaTemplateStatus
  ): Promise<WhatsAppTemplate | undefined> {
    return templateStore.updateStatus(id, status, metaStatus);
  }

  /**
   * Deletes a template.
   */
  public static async deleteTemplate(id: string, businessId?: string): Promise<boolean> {
    return templateStore.delete(id, businessId);
  }
}
