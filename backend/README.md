# GlowBlast Backend — Meta WhatsApp Cloud API Service

Lightweight, secure Node.js + TypeScript service that connects the GlowBlast Flutter application to the official Meta WhatsApp Cloud API.

---

## 1. Quick Start

### Prerequisites
* Node.js v20+ or v22+
* npm v10+

### Installation & Build
```bash
cd backend
npm install
npm run build
```

### Running Tests
```bash
npm test
```

### Running the Server
```bash
# Production mode
npm start

# Development mode with hot-reload
npm run dev
```

---

## 2. Environment Configuration (`.env`)

Copy `.env.example` to `.env`:
```bash
cp .env.example .env
```

| Variable | Description | Default / Example |
| :--- | :--- | :--- |
| `PORT` | Local server port | `3000` |
| `WHATSAPP_API_VERSION` | Current Meta Graph API version | `v22.0` |
| `WHATSAPP_PHONE_NUMBER_ID` | Meta Phone Number ID | `1272717865934207` |
| `WHATSAPP_BUSINESS_ACCOUNT_ID` | Meta WABA ID | `1633948435034571` |
| `TEST_WHATSAPP_DISPLAY_NUMBER`| Meta Test Number display | `+1 (555) 632-5494` |
| `WHATSAPP_ACCESS_TOKEN` | Meta System User / Temp Token (SECRET) | *Must be provided in server env* |
| `META_VERIFY_TOKEN` | Webhook verification token | `glowblast_webhook_verify_token` |
| `TEST_RECIPIENT_LIMIT` | Hard limit for test sends | `5` |
| `TEST_RECIPIENTS` | Allowlist of authorized test numbers | `919876543210,919123456789` |

> [!IMPORTANT]
> **NEVER commit `.env` or put `WHATSAPP_ACCESS_TOKEN` into Flutter or the mobile APK.** The access token exists strictly on the server.

---

## 3. Meta Dashboard Webhook Configuration

1. In **Meta for Developers Dashboard** -> **WhatsApp** -> **Configuration**.
2. Click **Edit** under **Webhook**.
3. **Callback URL:** `https://your-public-domain.com/api/webhook/whatsapp` (use ngrok or cloud domain).
4. **Verify Token:** `glowblast_webhook_verify_token` (matches `META_VERIFY_TOKEN` in `.env`).
5. Click **Verify and Save**.
6. Under Webhook fields, click **Manage** and subscribe to **`messages`**.

---

## 4. API Endpoints

* `GET /api/health` — Service health check.
* `GET /api/whatsapp/status` — Safe Meta configuration check (never returns tokens).
* `POST /api/whatsapp/send` — Direct single test message.
* `POST /api/campaigns/send` — Campaign dispatch (enforces <= 5 recipients, allowlist, opt-out suppression).
* `GET /api/campaigns/:campaignId` — Authoritative campaign status.
* `GET /api/campaigns/:campaignId/events` — Server-Sent Events (SSE) stream for live progress.
* `GET /api/webhook/whatsapp` — Meta webhook verification challenge.
* `POST /api/webhook/whatsapp` — Meta webhook status event listener.
