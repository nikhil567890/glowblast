import fs from 'fs';
import path from 'path';
import { StoredMessage, MessageStatus } from '../types/message';

const STATUS_PRECEDENCE: Record<MessageStatus, number> = {
  queued: 0,
  sending: 1,
  accepted: 2,
  sent: 3,
  delivered: 4,
  read: 5,
  failed: 10,
  excluded_opt_out: 10,
};

class MessageStore {
  private messages = new Map<string, StoredMessage>(); // key: internalId (e.g. campaignId_localCustomerId)
  private providerIdIndex = new Map<string, string>(); // providerMessageId -> internalId
  private storageFile: string;

  constructor() {
    const dataDir = path.join(process.cwd(), 'data');
    if (!fs.existsSync(dataDir)) {
      try {
        fs.mkdirSync(dataDir, { recursive: true });
      } catch {
        // Fallback for readonly filesystem in tests
      }
    }
    this.storageFile = path.join(dataDir, 'messages.json');
    this.loadFromDisk();
  }

  private loadFromDisk() {
    try {
      if (fs.existsSync(this.storageFile)) {
        const raw = fs.readFileSync(this.storageFile, 'utf8');
        const list: StoredMessage[] = JSON.parse(raw);
        for (const msg of list) {
          this.messages.set(msg.id, msg);
          if (msg.providerMessageId) {
            this.providerIdIndex.set(msg.providerMessageId, msg.id);
          }
        }
      }
    } catch {
      // Ignore initial file read errors
    }
  }

  private saveToDisk() {
    try {
      const list = Array.from(this.messages.values());
      fs.writeFileSync(this.storageFile, JSON.stringify(list, null, 2), 'utf8');
    } catch {
      // Ignore disk persistence errors in tests
    }
  }

  public get(id: string): StoredMessage | undefined {
    return this.messages.get(id);
  }

  public getByProviderId(providerMessageId: string): StoredMessage | undefined {
    const internalId = this.providerIdIndex.get(providerMessageId);
    if (!internalId) return undefined;
    return this.messages.get(internalId);
  }

  public getByCampaignId(campaignId: string): StoredMessage[] {
    return Array.from(this.messages.values()).filter((m) => m.campaignId === campaignId);
  }

  public upsert(msg: StoredMessage): StoredMessage {
    const existing = this.messages.get(msg.id);
    const updated: StoredMessage = {
      ...existing,
      ...msg,
      updatedAt: new Date().toISOString(),
    };
    this.messages.set(msg.id, updated);
    if (updated.providerMessageId) {
      this.providerIdIndex.set(updated.providerMessageId, updated.id);
    }
    this.saveToDisk();
    return updated;
  }

  /**
   * Updates message status enforcing monotonic progression.
   * A higher status (e.g. read, delivered) will never be overwritten by a lower status (e.g. sent, accepted).
   */
  public updateStatus(
    id: string,
    status: MessageStatus,
    providerMessageId?: string,
    error?: { code?: number; title?: string; message?: string; details?: string }
  ): StoredMessage | undefined {
    const msg = this.messages.get(id);
    if (!msg) return undefined;

    const currentWeight = STATUS_PRECEDENCE[msg.status] ?? 0;
    const newWeight = STATUS_PRECEDENCE[status] ?? 0;

    // Enforce monotonic progression: do not overwrite a higher status with an earlier status
    // Exception: transition to failed or excluded_opt_out is always allowed unless already failed/excluded
    const isTerminal = status === 'failed' || status === 'excluded_opt_out';
    const isCurrentTerminal = msg.status === 'failed' || msg.status === 'excluded_opt_out';

    if (isCurrentTerminal) {
      // Once failed or excluded, ignore earlier status webhooks
      if (!isTerminal) {
        console.log(`[MessageStore] Ignoring status '${status}' for terminal message ${id} (${msg.status})`);
      }
    } else if (newWeight >= currentWeight || isTerminal) {
      msg.status = status;
    } else {
      console.log(
        `[MessageStore] Preserving higher status '${msg.status}' over incoming earlier status '${status}' for ${id}`
      );
    }

    if (providerMessageId) {
      msg.providerMessageId = providerMessageId;
      this.providerIdIndex.set(providerMessageId, msg.id);
    }
    if (error) {
      msg.errorCode = error.code;
      msg.errorTitle = error.title;
      msg.errorMessage = error.message;
      if (error.details) {
        msg.errorDetails = error.details;
      }
    }
    msg.updatedAt = new Date().toISOString();
    this.saveToDisk();
    return msg;
  }

  public clear(): void {
    this.messages.clear();
    this.providerIdIndex.clear();
    this.saveToDisk();
  }
}

export const messageStore = new MessageStore();

