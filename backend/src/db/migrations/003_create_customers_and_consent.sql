-- 003_create_customers_and_consent.sql
CREATE TABLE IF NOT EXISTS customers (
    id VARCHAR(64) PRIMARY KEY,
    normalized_phone VARCHAR(32) NOT NULL,
    display_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_customers_phone ON customers (normalized_phone);

CREATE TABLE IF NOT EXISTS customer_consent (
    normalized_phone VARCHAR(32) PRIMARY KEY,
    customer_id VARCHAR(64) REFERENCES customers(id) ON DELETE SET NULL,
    status VARCHAR(32) NOT NULL CHECK (status IN ('opted_in', 'opted_out', 'revoked')),
    recorded_at TIMESTAMPTZ NOT NULL,
    source VARCHAR(128) NOT NULL,
    evidence TEXT NOT NULL,
    updated_by VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_customer_consent_status ON customer_consent (status);

CREATE TABLE IF NOT EXISTS consent_audit_log (
    id BIGSERIAL PRIMARY KEY,
    normalized_phone VARCHAR(32) NOT NULL,
    action VARCHAR(64) NOT NULL CHECK (action IN (
        'initial_opt_in', 'opt_in', 'opt_in_update', 'opt_in_override_of_opt_out',
        'opt_in_reinstatement', 'initial_opt_out', 'opt_out', 'opt_out_reaffirmation',
        'consent_revoked', 'status_update'
    )),
    previous_status VARCHAR(32),
    new_status VARCHAR(32) NOT NULL,
    source VARCHAR(128) NOT NULL,
    evidence TEXT NOT NULL,
    actor VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_consent_audit_phone ON consent_audit_log (normalized_phone, created_at DESC);
