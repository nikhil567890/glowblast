import fs from 'fs';
import path from 'path';
import crypto from 'crypto';

interface TemplateRecord {
  id: string;
  name: string;
  displayName?: string;
  category?: string;
  language?: string;
  status?: string;
  metaStatus?: string;
  body?: string;
  variables?: string[];
  mode?: string;
  wabaId?: string;
}

interface CampaignRecord {
  campaignId: string;
  clientRequestToken?: string;
  campaignName: string;
  mode?: string;
  status: string;
  templateName?: string;
  templateLanguage?: string;
  total?: number;
  accepted?: number;
  sent?: number;
  delivered?: number;
  read?: number;
  failed?: number;
  excludedOptOut?: number;
  messages?: any[];
  createdAt?: string;
  updatedAt?: string;
}

interface MessageRecord {
  id: string;
  campaignId: string;
  localCustomerId?: string;
  recipientName?: string;
  normalizedPhone: string;
  status: string;
  templateName?: string;
  templateLanguage?: string;
  providerMessageId?: string;
  createdAt?: string;
  updatedAt?: string;
}

interface ConsentRecord {
  phone: string;
  status: string;
  source?: string;
  evidenceText?: string;
  updatedBy?: string;
}

function calculateFileSha256(filePath: string): string {
  if (!fs.existsSync(filePath)) return 'FILE_NOT_FOUND';
  const buffer = fs.readFileSync(filePath);
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

export function runDryRunImport(dataDir: string): {
  checksums: Record<string, string>;
  counts: Record<string, { total: number; valid: number; invalid: number; duplicates: number }>;
  foreignKeyErrors: string[];
  issues: string[];
} {
  console.log('=================================================================');
  console.log(' GLOWBLAST JSON MIGRATION IMPORT TOOL (DRY-RUN VALIDATION ONLY)');
  console.log('=================================================================');
  console.log(`Source Directory: ${dataDir}`);
  console.log('Dry Run Mode: ACTIVE (No records will be inserted into PostgreSQL)');
  console.log('');

  const files = {
    templates: path.join(dataDir, 'templates.json'),
    campaigns: path.join(dataDir, 'campaigns.json'),
    messages: path.join(dataDir, 'messages.json'),
    consent: path.join(dataDir, 'consent_registry.json'),
    businesses: path.join(dataDir, 'businesses.json'),
  };

  const checksums: Record<string, string> = {};
  for (const [key, filePath] of Object.entries(files)) {
    checksums[key] = calculateFileSha256(filePath);
  }

  const counts: Record<string, { total: number; valid: number; invalid: number; duplicates: number }> = {
    templates: { total: 0, valid: 0, invalid: 0, duplicates: 0 },
    campaigns: { total: 0, valid: 0, invalid: 0, duplicates: 0 },
    messages: { total: 0, valid: 0, invalid: 0, duplicates: 0 },
    consent: { total: 0, valid: 0, invalid: 0, duplicates: 0 },
  };

  const foreignKeyErrors: string[] = [];
  const issues: string[] = [];

  // 1. Templates Validation
  const templateIds = new Set<string>();
  if (fs.existsSync(files.templates)) {
    try {
      const templates: TemplateRecord[] = JSON.parse(fs.readFileSync(files.templates, 'utf8'));
      counts.templates.total = templates.length;
      for (const tpl of templates) {
        if (!tpl.id || !tpl.name) {
          counts.templates.invalid++;
          issues.push(`Template missing required id or name: ${JSON.stringify(tpl)}`);
          continue;
        }
        if (templateIds.has(tpl.id)) {
          counts.templates.duplicates++;
          issues.push(`Duplicate template ID: ${tpl.id}`);
          continue;
        }
        templateIds.add(tpl.id);
        counts.templates.valid++;
      }
    } catch (err: any) {
      issues.push(`Failed to parse templates.json: ${err.message}`);
    }
  }

  // 2. Campaigns Validation
  const campaignIds = new Set<string>();
  if (fs.existsSync(files.campaigns)) {
    try {
      const campaigns: CampaignRecord[] = JSON.parse(fs.readFileSync(files.campaigns, 'utf8'));
      counts.campaigns.total = campaigns.length;
      for (const camp of campaigns) {
        if (!camp.campaignId || !camp.campaignName) {
          counts.campaigns.invalid++;
          issues.push(`Campaign missing required campaignId or campaignName: ${JSON.stringify(camp)}`);
          continue;
        }
        if (campaignIds.has(camp.campaignId)) {
          counts.campaigns.duplicates++;
          issues.push(`Duplicate campaign ID: ${camp.campaignId}`);
          continue;
        }
        campaignIds.add(camp.campaignId);
        counts.campaigns.valid++;
      }
    } catch (err: any) {
      issues.push(`Failed to parse campaigns.json: ${err.message}`);
    }
  }

  // 3. Messages Validation & Foreign-Key Integrity
  const messageIds = new Set<string>();
  const campaignPhonePairs = new Set<string>();

  if (fs.existsSync(files.messages)) {
    try {
      const messages: MessageRecord[] = JSON.parse(fs.readFileSync(files.messages, 'utf8'));
      counts.messages.total = messages.length;
      for (const msg of messages) {
        if (!msg.id || !msg.campaignId || !msg.normalizedPhone) {
          counts.messages.invalid++;
          issues.push(`Message missing id, campaignId, or normalizedPhone: ${msg.id || 'unknown'}`);
          continue;
        }
        if (messageIds.has(msg.id)) {
          counts.messages.duplicates++;
          issues.push(`Duplicate message ID: ${msg.id}`);
          continue;
        }
        messageIds.add(msg.id);

        // Check foreign key: campaignId must exist in campaigns.json
        if (!campaignIds.has(msg.campaignId)) {
          foreignKeyErrors.push(`Message ${msg.id} references non-existent campaignId: ${msg.campaignId}`);
          counts.messages.invalid++;
          continue;
        }

        const pairKey = `${msg.campaignId}:${msg.normalizedPhone}`;
        if (campaignPhonePairs.has(pairKey)) {
          // In some old test runs, same recipient might have been included twice
          issues.push(`Warning: Multiple messages for phone in same campaign: ${pairKey} (msg: ${msg.id})`);
        }
        campaignPhonePairs.add(pairKey);

        counts.messages.valid++;
      }
    } catch (err: any) {
      issues.push(`Failed to parse messages.json: ${err.message}`);
    }
  }

  // 4. Consent Registry Validation (DO NOT infer consent from campaigns or messages!)
  const consentPhones = new Set<string>();
  if (fs.existsSync(files.consent)) {
    try {
      const raw = fs.readFileSync(files.consent, 'utf8').trim();
      const consents = raw ? JSON.parse(raw) : [];
      const list: ConsentRecord[] = Array.isArray(consents) ? consents : Object.values(consents);
      counts.consent.total = list.length;
      for (const c of list) {
        if (!c.phone || !c.status) {
          counts.consent.invalid++;
          continue;
        }
        if (consentPhones.has(c.phone)) {
          counts.consent.duplicates++;
          continue;
        }
        consentPhones.add(c.phone);
        counts.consent.valid++;
      }
    } catch (err: any) {
      issues.push(`Failed to parse consent_registry.json: ${err.message}`);
    }
  }

  console.log('--- FILE SHA-256 CHECKSUMS ---');
  for (const [key, hash] of Object.entries(checksums)) {
    console.log(`  ${key.padEnd(12)}: ${hash}`);
  }
  console.log('');

  console.log('--- RECORD COUNTS & VALIDATION ---');
  for (const [key, stat] of Object.entries(counts)) {
    console.log(
      `  ${key.padEnd(12)}: total=${stat.total}, valid=${stat.valid}, duplicates=${stat.duplicates}, invalid=${stat.invalid}`
    );
  }
  console.log('');

  if (foreignKeyErrors.length > 0) {
    console.log(`--- FOREIGN KEY INTEGRITY WARNINGS (${foreignKeyErrors.length}) ---`);
    for (const err of foreignKeyErrors.slice(0, 10)) {
      console.log(`  [FK] ${err}`);
    }
    if (foreignKeyErrors.length > 10) {
      console.log(`  ... and ${foreignKeyErrors.length - 10} more`);
    }
    console.log('');
  }

  console.log(`Total Validation Issues/Warnings: ${issues.length}`);
  console.log('Database Write Action: NONE (Dry-run mode strictly enforced)');
  console.log('=================================================================');

  return { checksums, counts, foreignKeyErrors, issues };
}

if (require.main === module || process.argv[1]?.includes('dryRunImport')) {
  const dataDir = process.env.DATA_DIR || path.join(__dirname, '..', 'data');
  runDryRunImport(dataDir);
}
