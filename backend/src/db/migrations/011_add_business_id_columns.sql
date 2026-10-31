-- Migration 011: Add nullable business_id columns and indexes to all tenant-scoped data tables
-- These are added as NULLABLE first so that the existing application continues
-- functioning while the backfill migration (012) populates them.
-- Non-null constraints are intentionally deferred to future phases to guarantee zero downtime
-- and backwards compatibility with existing clients and write paths.

-- 1. customers
ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES businesses(id);
CREATE INDEX IF NOT EXISTS idx_customers_business_id ON customers(business_id);

-- 2. customer_consent
ALTER TABLE customer_consent
  ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES businesses(id);
CREATE INDEX IF NOT EXISTS idx_customer_consent_business_id ON customer_consent(business_id);

-- 3. consent_audit_log
ALTER TABLE consent_audit_log
  ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES businesses(id);
CREATE INDEX IF NOT EXISTS idx_consent_audit_log_business_id ON consent_audit_log(business_id);

-- 4. campaigns
ALTER TABLE campaigns
  ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES businesses(id);
CREATE INDEX IF NOT EXISTS idx_campaigns_business_id ON campaigns(business_id);

-- 5. campaign_messages (denormalized for fast tenant isolation & status lookups)
ALTER TABLE campaign_messages
  ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES businesses(id);
CREATE INDEX IF NOT EXISTS idx_campaign_messages_business_id ON campaign_messages(business_id);

-- 6. whatsapp_templates
ALTER TABLE whatsapp_templates
  ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES businesses(id);
CREATE INDEX IF NOT EXISTS idx_whatsapp_templates_business_id ON whatsapp_templates(business_id);

-- 7. webhook_events
ALTER TABLE webhook_events
  ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES businesses(id);
CREATE INDEX IF NOT EXISTS idx_webhook_events_business_id ON webhook_events(business_id);

-- 8. recipient_reservations
ALTER TABLE recipient_reservations
  ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES businesses(id);
CREATE INDEX IF NOT EXISTS idx_recipient_reservations_business_id ON recipient_reservations(business_id);
