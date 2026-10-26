-- Migration 010: Create business_members table for multi-business membership
-- Associates authenticated users with businesses and defines their role (owner, admin, staff).

CREATE TABLE IF NOT EXISTS business_members (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id     VARCHAR(64) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role        VARCHAR(20) NOT NULL DEFAULT 'staff'
              CHECK (role IN ('owner', 'admin', 'staff')),
  invited_by  VARCHAR(64) REFERENCES users(id),
  joined_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE (business_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_members_user ON business_members(user_id);
CREATE INDEX IF NOT EXISTS idx_members_business ON business_members(business_id);
CREATE INDEX IF NOT EXISTS idx_members_role ON business_members(business_id, role);
