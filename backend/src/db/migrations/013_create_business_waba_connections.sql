-- Migration 013: Create business_waba_connections table for multi-business WhatsApp accounts
-- Stores encrypted Meta WhatsApp Cloud API credentials per business.
-- Enforces tenant isolation, token security, and single active phone number mapping per mode.

CREATE TABLE IF NOT EXISTS business_waba_connections (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id             UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  waba_id                 VARCHAR(64) NOT NULL,
  phone_number_id         VARCHAR(64) NOT NULL,
  display_number          VARCHAR(32),
  mode                    VARCHAR(20) NOT NULL DEFAULT 'production'
                          CHECK (mode IN ('test', 'production')),
  is_active               BOOLEAN NOT NULL DEFAULT true,
  -- Authenticated AES-256-GCM encrypted token material
  encrypted_access_token  TEXT NOT NULL,
  token_iv                VARCHAR(64) NOT NULL,
  token_tag               VARCHAR(64) NOT NULL,
  key_id                  VARCHAR(32) DEFAULT 'v1',
  -- Meta metadata for verified WABA and Embedded Signup tracking
  meta_app_id             VARCHAR(64),
  verified_name           VARCHAR(255),
  quality_rating          VARCHAR(32) DEFAULT 'UNKNOWN',
  code_verification_status VARCHAR(64),
  created_at              TIMESTAMPTZ DEFAULT NOW(),
  updated_at              TIMESTAMPTZ DEFAULT NOW()
);

-- Index for resolving connections by verified business
CREATE INDEX IF NOT EXISTS idx_waba_connections_biz ON business_waba_connections(business_id);

-- Index for webhook incoming routing by receiving phone_number_id
CREATE INDEX IF NOT EXISTS idx_waba_connections_phone ON business_waba_connections(phone_number_id);

-- Index for template sync by Meta WABA ID
CREATE INDEX IF NOT EXISTS idx_waba_connections_waba ON business_waba_connections(waba_id);

-- Uniqueness constraint 1: A business can have at most ONE active connection per mode (test or production)
CREATE UNIQUE INDEX IF NOT EXISTS uq_biz_active_waba_mode
  ON business_waba_connections(business_id, mode)
  WHERE is_active = true;

-- Uniqueness constraint 2: A phone_number_id cannot be actively assigned to multiple businesses in the same mode
CREATE UNIQUE INDEX IF NOT EXISTS uq_active_phone_number_mode
  ON business_waba_connections(phone_number_id, mode)
  WHERE is_active = true;
