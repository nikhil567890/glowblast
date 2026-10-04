import fs from 'fs';
import path from 'path';
import { StoredMessage, MessageStatus } from '../types/message';

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

  public updateStatus(
    id: string,
    status: MessageStatus,
    providerMessageId?: string,
    error?: { code?: number; title?: string; message?: string }
  ): StoredMessage | undefined {
    const msg = this.messages.get(id);
    if (!msg) return undefined;

    msg.status = status;
    if (providerMessageId) {
      msg.providerMessageId = providerMessageId;
      this.providerIdIndex.set(providerMessageId, msg.id);
    }
    if (error) {
      msg.errorCode = error.code;
      msg.errorTitle = error.title;
      msg.errorMessage = error.message;
    }
    msg.updatedAt = new Date().toISOString();
    this.saveToDisk();
    return msg;
  }
}

export const messageStore = new MessageStore();
