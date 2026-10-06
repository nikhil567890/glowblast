import fs from 'fs';
import path from 'path';
import { WhatsAppTemplate, TemplateApprovalStatus, MetaTemplateStatus } from '../types/template';

const SEED_TEMPLATES: WhatsAppTemplate[] = [
  {
    id: 'tpl_hello_world',
    name: 'hello_world',
    displayName: 'Meta Test Default (Hello World)',
    description: 'Official Meta WhatsApp Cloud API default test template (no parameters). Pre-approved on all Meta test numbers.',
    category: 'UTILITY',
    language: 'en_US',
    status: 'approved',
    metaStatus: 'APPROVED',
    body: 'Hello World',
    variables: [],
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
  },
  {
    id: 'tpl_birthday',
    name: 'birthday_offer',
    displayName: 'Birthday Pampering',
    description: 'Celebratory birthday greeting with personalized 25% discount. (Draft - requires Meta submission/approval)',
    category: 'MARKETING',
    language: 'en_US',
    status: 'draft',
    metaStatus: 'NOT_SUBMITTED',
    body: '🎂 Happy Birthday month, {name}! Celebrate your special day with our rejuvenating therapy at {business_name}. Enjoy 25% OFF on any 90-minute treatment this month. Reply BOOK to reserve!',
    variables: ['name', 'business_name'],
    exampleValues: {
      name: 'Nikhil',
      business_name: 'Luxspa',
    },
    createdAt: '2026-02-01T00:00:00.000Z',
    updatedAt: '2026-02-01T00:00:00.000Z',
  },
  {
    id: 'tpl_diwali',
    name: 'diwali_offer',
    displayName: 'Diwali Festive Radiance',
    description: 'Festive radiance offer with flat 35% discount. (Draft - requires Meta submission/approval)',
    category: 'MARKETING',
    language: 'en_US',
    status: 'draft',
    metaStatus: 'NOT_SUBMITTED',
    body: '✨ Sparkle & Glow this Diwali! Indulge in our Festive Radiance Ritual at {business_name} with flat 35% OFF until Diwali eve. Treat yourself or gift a loved one! Reply YES to book.',
    variables: ['business_name'],
    exampleValues: {
      business_name: 'Luxspa & Wellness',
    },
    createdAt: '2026-02-01T00:00:00.000Z',
    updatedAt: '2026-02-01T00:00:00.000Z',
  },
  {
    id: 'tpl_reminder',
    name: 'appointment_reminder',
    displayName: 'Appointment Reminder',
    description: 'Pre-visit confirmation and timing reminder. (Draft - requires Meta submission/approval)',
    category: 'UTILITY',
    language: 'en_US',
    status: 'draft',
    metaStatus: 'NOT_SUBMITTED',
    body: '🌸 Hi {name}, this is a gentle reminder for your upcoming appointment at {business_name}. Please arrive 10 minutes early to enjoy our warm herbal welcome tea.',
    variables: ['name', 'business_name'],
    exampleValues: {
      name: 'Ananya',
      business_name: 'Our Spa & Wellness',
    },
    createdAt: '2026-02-01T00:00:00.000Z',
    updatedAt: '2026-02-01T00:00:00.000Z',
  },
  {
    id: 'tpl_vip_draft',
    name: 'vip_exclusive_access',
    displayName: 'VIP Exclusive Access (Draft)',
    description: 'Local draft template awaiting finalization. Cannot be dispatched until submitted and approved by Meta.',
    category: 'MARKETING',
    language: 'en_US',
    status: 'draft',
    metaStatus: 'NOT_SUBMITTED',
    body: '✨ Exclusive VIP invitation for {name} from {business_name}. Enjoy priority booking!',
    variables: ['name', 'business_name'],
    createdAt: '2026-03-01T00:00:00.000Z',
    updatedAt: '2026-03-01T00:00:00.000Z',
  },
  {
    id: 'tpl_festival_pending',
    name: 'festival_super_sale',
    displayName: 'Festival Super Sale (Pending Meta Approval)',
    description: 'Submitted to Meta WhatsApp Business Platform and currently under review. Cannot be dispatched until approved.',
    category: 'MARKETING',
    language: 'en_US',
    status: 'pending_approval',
    metaStatus: 'PENDING',
    body: '🎉 Grand Festive Sale at {business_name}! Enjoy 40% OFF all therapies this weekend, {name}!',
    variables: ['business_name', 'name'],
    createdAt: '2026-03-05T00:00:00.000Z',
    updatedAt: '2026-03-05T00:00:00.000Z',
  },
];

class TemplateStore {
  private templates = new Map<string, WhatsAppTemplate>(); // key: id or name
  private storageFile: string;

  constructor() {
    const dataDir = path.join(process.cwd(), 'data');
    if (!fs.existsSync(dataDir)) {
      try {
        fs.mkdirSync(dataDir, { recursive: true });
      } catch {
        // Fallback
      }
    }
    this.storageFile = path.join(dataDir, 'templates.json');
    this.loadFromDisk();
  }

  private loadFromDisk() {
    try {
      if (fs.existsSync(this.storageFile)) {
        const raw = fs.readFileSync(this.storageFile, 'utf8');
        const list: WhatsAppTemplate[] = JSON.parse(raw);
        for (const tpl of list) {
          this.templates.set(tpl.id, tpl);
        }
      }
    } catch {
      // Ignore
    }

    // Seed defaults if empty
    if (this.templates.size === 0) {
      for (const tpl of SEED_TEMPLATES) {
        this.templates.set(tpl.id, tpl);
      }
      this.saveToDisk();
    }
  }

  private saveToDisk() {
    try {
      const list = Array.from(this.templates.values());
      fs.writeFileSync(this.storageFile, JSON.stringify(list, null, 2), 'utf8');
    } catch {
      // Ignore
    }
  }

  public getAll(): WhatsAppTemplate[] {
    return Array.from(this.templates.values());
  }

  public getById(id: string): WhatsAppTemplate | undefined {
    return this.templates.get(id);
  }

  public get(idOrName: string): WhatsAppTemplate | undefined {
    return this.findByIdOrName(idOrName);
  }

  public getApproved(): WhatsAppTemplate[] {
    return Array.from(this.templates.values()).filter((t) => t.status === 'approved');
  }

  public getByName(name: string): WhatsAppTemplate | undefined {
    return Array.from(this.templates.values()).find(
      (t) => t.name.toLowerCase() === name.toLowerCase()
    );
  }

  public findByIdOrName(idOrName: string): WhatsAppTemplate | undefined {
    return (
      this.templates.get(idOrName) ||
      Array.from(this.templates.values()).find(
        (t) => t.name.toLowerCase() === idOrName.toLowerCase()
      )
    );
  }

  public create(tpl: WhatsAppTemplate): WhatsAppTemplate {
    this.templates.set(tpl.id, tpl);
    this.saveToDisk();
    return tpl;
  }

  public update(id: string, updates: Partial<WhatsAppTemplate>): WhatsAppTemplate | undefined {
    const existing = this.templates.get(id);
    if (!existing) return undefined;

    const updated: WhatsAppTemplate = {
      ...existing,
      ...updates,
      updatedAt: new Date().toISOString(),
    };
    this.templates.set(id, updated);
    this.saveToDisk();
    return updated;
  }

  public updateStatus(
    id: string,
    status: TemplateApprovalStatus,
    metaStatus?: MetaTemplateStatus
  ): WhatsAppTemplate | undefined {
    const tpl = this.templates.get(id);
    if (!tpl) return undefined;

    tpl.status = status;
    if (metaStatus) {
      tpl.metaStatus = metaStatus;
    }
    tpl.updatedAt = new Date().toISOString();
    this.saveToDisk();
    return tpl;
  }

  public delete(id: string): boolean {
    const existed = this.templates.delete(id);
    if (existed) {
      this.saveToDisk();
    }
    return existed;
  }

  public clear(): void {
    this.templates.clear();
    for (const tpl of SEED_TEMPLATES) {
      this.templates.set(tpl.id, tpl);
    }
    this.saveToDisk();
  }
}

export const templateStore = new TemplateStore();
