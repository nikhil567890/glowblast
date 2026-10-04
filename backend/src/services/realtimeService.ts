import { Response } from 'express';
import { campaignStore } from '../store/campaignStore';
import { maskPhone } from '../utils/phone';

interface SSEClient {
  res: Response;
  campaignId: string;
}

class RealtimeService {
  private clients: SSEClient[] = [];

  constructor() {
    // Heartbeat every 15 seconds to prevent client timeout
    const timer = setInterval(() => {
      this.sendHeartbeat();
    }, 15000);
    timer.unref();
  }

  public registerClient(campaignId: string, res: Response) {
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.flushHeaders();

    const client: SSEClient = { res, campaignId };
    this.clients.push(client);

    console.log(`[SSE] Client connected for campaign ${campaignId}`);

    // Send immediate initial campaign state
    const summary = campaignStore.getSummary(campaignId);
    if (summary) {
      this.sendToClient(client, 'campaign_progress', summary);
    }

    res.on('close', () => {
      this.clients = this.clients.filter((c) => c !== client);
      console.log(`[SSE] Client disconnected for campaign ${campaignId}`);
    });
  }

  private sendHeartbeat() {
    for (const client of this.clients) {
      try {
        client.res.write(': keep-alive\n\n');
      } catch {
        // Ignored
      }
    }
  }

  private sendToClient(client: SSEClient, event: string, data: any) {
    try {
      client.res.write(`event: ${event}\n`);
      client.res.write(`data: ${JSON.stringify(data)}\n\n`);
    } catch {
      // Ignored
    }
  }

  public broadcastMessageStatus(payload: {
    campaignId: string;
    phone: string;
    status: string;
    providerMessageId?: string;
    errorCode?: number;
    errorTitle?: string;
  }) {
    console.log(
      `[SSE] Emit message_status for campaign ${payload.campaignId}: ${maskPhone(payload.phone)} -> ${payload.status}`
    );

    const relevantClients = this.clients.filter((c) => c.campaignId === payload.campaignId);
    for (const client of relevantClients) {
      this.sendToClient(client, 'message_status', {
        type: 'message_status',
        ...payload,
      });
    }

    // Also broadcast updated progress
    this.broadcastCampaignProgress(payload.campaignId);
  }

  public broadcastCampaignProgress(campaignId: string) {
    const summary = campaignStore.getSummary(campaignId);
    if (!summary) return;

    const relevantClients = this.clients.filter((c) => c.campaignId === campaignId);
    for (const client of relevantClients) {
      this.sendToClient(client, 'campaign_progress', {
        type: 'campaign_progress',
        ...summary,
        processed: summary.accepted + summary.failed + summary.excludedOptOut,
      });
    }
  }
}

export const realtimeService = new RealtimeService();
