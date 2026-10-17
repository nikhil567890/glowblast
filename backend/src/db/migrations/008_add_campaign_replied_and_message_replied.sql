-- 008_add_campaign_replied_and_message_replied.sql
-- Adds explicit count_replied to campaigns and replied_at timestamp to campaign_messages
-- for genuine, verified WhatsApp inbound reply tracking.

ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS count_replied INTEGER NOT NULL DEFAULT 0;
ALTER TABLE campaign_messages ADD COLUMN IF NOT EXISTS replied_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_campaign_messages_replied 
    ON campaign_messages (campaign_id, replied_at) 
    WHERE replied_at IS NOT NULL;
