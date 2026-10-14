-- 005_create_campaigns_and_messages.sql
CREATE TABLE IF NOT EXISTS campaigns (
    campaign_id VARCHAR(128) PRIMARY KEY,
    client_request_token VARCHAR(36),
    user_id VARCHAR(64) REFERENCES users(id) ON DELETE SET NULL,
    campaign_name VARCHAR(255) NOT NULL,
    business_name VARCHAR(255),
    mode VARCHAR(16) NOT NULL CHECK (mode IN ('test', 'production', 'demo')),
    status VARCHAR(32) NOT NULL CHECK (status IN ('pending', 'processing', 'accepted', 'completed', 'completed_with_errors', 'failed', 'cancelled')),
    template_name VARCHAR(128) NOT NULL,
    template_language VARCHAR(16) NOT NULL DEFAULT 'en_US',
    total_recipients INTEGER NOT NULL DEFAULT 0,
    count_queued INTEGER NOT NULL DEFAULT 0,
    count_accepted INTEGER NOT NULL DEFAULT 0,
    count_sent INTEGER NOT NULL DEFAULT 0,
    count_delivered INTEGER NOT NULL DEFAULT 0,
    count_read INTEGER NOT NULL DEFAULT 0,
    count_failed INTEGER NOT NULL DEFAULT 0,
    count_excluded_opt_out INTEGER NOT NULL DEFAULT 0,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Standard unique index (permits multiple NULLs, strictly enforces uniqueness for non-NULL client_request_tokens)
CREATE UNIQUE INDEX IF NOT EXISTS uq_campaigns_client_request_token ON campaigns (client_request_token);
CREATE INDEX IF NOT EXISTS idx_campaigns_created ON campaigns (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_campaigns_status ON campaigns (status);

CREATE TABLE IF NOT EXISTS campaign_messages (
    id VARCHAR(192) PRIMARY KEY,
    campaign_id VARCHAR(128) NOT NULL REFERENCES campaigns(campaign_id) ON DELETE CASCADE,
    local_customer_id VARCHAR(64) NOT NULL,
    recipient_name VARCHAR(255) NOT NULL,
    normalized_phone VARCHAR(32) NOT NULL,
    status VARCHAR(32) NOT NULL CHECK (status IN (
        'queued', 'sending', 'accepted', 'sent', 'delivered',
        'read', 'failed', 'excluded_opt_out', 'uncertain_timeout'
    )),
    provider_message_id VARCHAR(128),
    template_name VARCHAR(128),
    template_language VARCHAR(16),
    error_code INTEGER,
    error_title VARCHAR(255),
    error_message TEXT,
    error_details TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_campaign_messages_campaign_phone ON campaign_messages (campaign_id, normalized_phone);
CREATE UNIQUE INDEX IF NOT EXISTS uq_campaign_messages_provider_id ON campaign_messages (provider_message_id) WHERE provider_message_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_campaign_messages_campaign ON campaign_messages (campaign_id);
CREATE INDEX IF NOT EXISTS idx_campaign_messages_status ON campaign_messages (status);
