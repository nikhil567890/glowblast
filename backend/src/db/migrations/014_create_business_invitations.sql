-- Migration 014: Create business_invitations table for team management
-- Stores secure email invitation tokens with expiry and role assignments.

CREATE TABLE IF NOT EXISTS business_invitations (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id  UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  email        VARCHAR(255) NOT NULL,
  role         VARCHAR(20) NOT NULL DEFAULT 'staff'
               CHECK (role IN ('admin', 'staff')),
  token        VARCHAR(128) UNIQUE NOT NULL,
  invited_by   VARCHAR(64) NOT NULL REFERENCES users(id),
  status       VARCHAR(20) NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending', 'accepted', 'revoked', 'expired')),
  expires_at   TIMESTAMPTZ NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for looking up invitations by business
CREATE INDEX IF NOT EXISTS idx_invitations_biz ON business_invitations(business_id);

-- Index for resolving invitation by token
CREATE INDEX IF NOT EXISTS idx_invitations_token ON business_invitations(token);

-- Index for searching invitations by email
CREATE INDEX IF NOT EXISTS idx_invitations_email ON business_invitations(LOWER(email));

-- Prevent multiple pending invitations to the same email for the same business
CREATE UNIQUE INDEX IF NOT EXISTS uq_pending_biz_email
  ON business_invitations (business_id, LOWER(email))
  WHERE status = 'pending';
