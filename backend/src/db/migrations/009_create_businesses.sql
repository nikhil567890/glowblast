-- Migration 009: Create businesses table for multi-business SaaS support
-- Each business represents an independent spa/wellness tenant on the platform.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS businesses (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug                VARCHAR(63) UNIQUE NOT NULL,
  display_name        VARCHAR(255) NOT NULL,
  owner_user_id       VARCHAR(64) NOT NULL REFERENCES users(id),
  phone               VARCHAR(32),
  email               VARCHAR(255),
  timezone            VARCHAR(50) DEFAULT 'Asia/Kolkata',
  logo_url            TEXT,
  is_active           BOOLEAN DEFAULT true,
  production_enabled  BOOLEAN DEFAULT false,
  daily_recipient_limit INTEGER DEFAULT 200,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_businesses_owner ON businesses(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_businesses_slug ON businesses(slug);
CREATE INDEX IF NOT EXISTS idx_businesses_active ON businesses(is_active) WHERE is_active = true;
