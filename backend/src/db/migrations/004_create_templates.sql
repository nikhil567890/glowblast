-- 004_create_templates.sql
CREATE TABLE IF NOT EXISTS whatsapp_templates (
    id VARCHAR(128) PRIMARY KEY,
    name VARCHAR(128) NOT NULL,
    display_name VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(32) NOT NULL CHECK (category IN ('MARKETING', 'UTILITY', 'AUTHENTICATION')),
    language VARCHAR(16) NOT NULL DEFAULT 'en_US',
    status VARCHAR(32) NOT NULL CHECK (status IN ('draft', 'pending_approval', 'approved', 'rejected', 'disabled')),
    meta_status VARCHAR(32) NOT NULL CHECK (meta_status IN ('APPROVED', 'PENDING', 'REJECTED', 'PAUSED', 'DISABLED', 'NOT_SUBMITTED')),
    meta_template_id VARCHAR(64),
    body TEXT NOT NULL,
    variables JSONB NOT NULL DEFAULT '[]'::jsonb,
    example_values JSONB,
    waba_id VARCHAR(64),
    mode VARCHAR(16) NOT NULL DEFAULT 'test' CHECK (mode IN ('test', 'production')),
    last_synced_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_templates_name_mode_lang ON whatsapp_templates (LOWER(name), mode, language);
CREATE INDEX IF NOT EXISTS idx_templates_status_mode ON whatsapp_templates (status, mode);
