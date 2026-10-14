-- 006_create_locks_reservations_and_webhooks.sql
CREATE TABLE IF NOT EXISTS app_locks (
    lock_key VARCHAR(64) PRIMARY KEY,
    description TEXT,
    locked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed quota reservation mutex row
INSERT INTO app_locks (lock_key, description, locked_at)
VALUES ('production_quota_reservation', 'Serializes 24h rolling quota check', NOW())
ON CONFLICT (lock_key) DO NOTHING;

CREATE TABLE IF NOT EXISTS recipient_reservations (
    id BIGSERIAL PRIMARY KEY,
    campaign_id VARCHAR(128) NOT NULL REFERENCES campaigns(campaign_id) ON DELETE CASCADE,
    normalized_phone VARCHAR(32) NOT NULL,
    reserved_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_reservations_campaign_phone ON recipient_reservations (campaign_id, normalized_phone);
CREATE INDEX IF NOT EXISTS idx_reservations_window ON recipient_reservations (reserved_at DESC, normalized_phone);

CREATE TABLE IF NOT EXISTS webhook_events (
    dedup_key VARCHAR(192) PRIMARY KEY,
    event_type VARCHAR(32) NOT NULL CHECK (event_type IN ('status', 'message')),
    provider_message_id VARCHAR(128) NOT NULL,
    status VARCHAR(32),
    payload JSONB NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_webhook_events_provider ON webhook_events (provider_message_id);
CREATE INDEX IF NOT EXISTS idx_webhook_events_received ON webhook_events (received_at DESC);
