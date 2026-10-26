-- GlowBlast Multi-Business SaaS: Pre-Migration & Post-Backfill Validation Queries
-- These read-only queries verify database state before and after running migrations 009 through 012.

--------------------------------------------------------------------------------
-- PART 1: PRE-MIGRATION AUDIT (Run before applying migrations)
--------------------------------------------------------------------------------

-- 1.1 Verify user accounts and check for owner ambiguity
SELECT 
  id, 
  email, 
  name, 
  business_name, 
  phone, 
  email_verified, 
  created_at
FROM users
ORDER BY created_at ASC;

-- 1.2 Ambiguity check: if count > 1, explicit owner confirmation is required
SELECT 
  COUNT(*) AS total_users,
  COUNT(*) FILTER (WHERE email_verified = true) AS verified_users,
  CASE 
    WHEN COUNT(*) FILTER (WHERE email_verified = true) = 1 THEN 'UNAMBIGUOUS_OWNER'
    WHEN COUNT(*) = 1 THEN 'UNAMBIGUOUS_SINGLE_USER'
    ELSE 'AMBIGUOUS_REQUIRES_CONFIRMATION'
  END AS owner_status
FROM users;

-- 1.3 Pre-migration record counts (baseline to verify no data loss)
SELECT 
  (SELECT COUNT(*) FROM customers) AS total_customers,
  (SELECT COUNT(*) FROM customer_consent) AS total_consent_records,
  (SELECT COUNT(*) FROM consent_audit_log) AS total_consent_audit_logs,
  (SELECT COUNT(*) FROM campaigns) AS total_campaigns,
  (SELECT COUNT(*) FROM campaign_messages) AS total_messages,
  (SELECT COUNT(*) FROM whatsapp_templates) AS total_templates,
  (SELECT COUNT(*) FROM webhook_events) AS total_webhook_events,
  (SELECT COUNT(*) FROM recipient_reservations) AS total_reservations;

--------------------------------------------------------------------------------
-- PART 2: POST-BACKFILL INTEGRITY VALIDATION (Run after applying 009-012)
--------------------------------------------------------------------------------

-- 2.1 Verify businesses and memberships exist (specifically checking canonical initial spa ID)
SELECT b.id AS business_id, b.slug, b.display_name, b.production_enabled, 
       bm.user_id AS owner_user_id, bm.role, u.email AS owner_email,
       CASE WHEN b.id = 'a0000000-0000-4000-8000-000000000001'::uuid THEN 'CANONICAL_INITIAL_SPA' ELSE 'CUSTOM_TENANT' END AS spa_type
FROM businesses b
LEFT JOIN business_members bm ON b.id = bm.business_id AND bm.role = 'owner'
LEFT JOIN users u ON bm.user_id = u.id;

-- 2.2 Verify ZERO unassigned records exist (Every record must belong to initial business)
SELECT 
  (SELECT COUNT(*) FROM customers WHERE business_id IS NULL) AS unassigned_customers,
  (SELECT COUNT(*) FROM customer_consent WHERE business_id IS NULL) AS unassigned_consent,
  (SELECT COUNT(*) FROM consent_audit_log WHERE business_id IS NULL) AS unassigned_consent_audit,
  (SELECT COUNT(*) FROM campaigns WHERE business_id IS NULL) AS unassigned_campaigns,
  (SELECT COUNT(*) FROM campaign_messages WHERE business_id IS NULL) AS unassigned_messages,
  (SELECT COUNT(*) FROM whatsapp_templates WHERE business_id IS NULL) AS unassigned_templates,
  (SELECT COUNT(*) FROM webhook_events WHERE business_id IS NULL) AS unassigned_webhook_events,
  (SELECT COUNT(*) FROM recipient_reservations WHERE business_id IS NULL) AS unassigned_reservations;

-- 2.3 Verify ZERO orphaned records (All business_ids point to a valid business)
SELECT 
  (SELECT COUNT(*) FROM customers WHERE business_id NOT IN (SELECT id FROM businesses)) AS orphaned_customers,
  (SELECT COUNT(*) FROM customer_consent WHERE business_id NOT IN (SELECT id FROM businesses)) AS orphaned_consent,
  (SELECT COUNT(*) FROM campaigns WHERE business_id NOT IN (SELECT id FROM businesses)) AS orphaned_campaigns,
  (SELECT COUNT(*) FROM campaign_messages WHERE business_id NOT IN (SELECT id FROM businesses)) AS orphaned_messages,
  (SELECT COUNT(*) FROM whatsapp_templates WHERE business_id NOT IN (SELECT id FROM businesses)) AS orphaned_templates;

-- 2.4 Verify existing relational integrity is 100% preserved
-- Customer <-> Consent relationship
SELECT COUNT(*) AS broken_consent_customer_links
FROM customer_consent cc
LEFT JOIN customers c ON cc.customer_id = c.id
WHERE cc.customer_id IS NOT NULL AND c.id IS NULL;

-- Campaign <-> Message relationship
SELECT COUNT(*) AS broken_campaign_message_links
FROM campaign_messages cm
LEFT JOIN campaigns c ON cm.campaign_id = c.campaign_id
WHERE c.campaign_id IS NULL;

-- 2.5 Verify opt-out and consent counts are identical to pre-migration baseline
SELECT 
  status, 
  consent_category, 
  COUNT(*) AS count
FROM customer_consent
GROUP BY status, consent_category
ORDER BY status, consent_category;

-- 2.6 Verify all verified users have a membership in the initial business (must be 0 unassigned)
SELECT COUNT(*) AS unassigned_verified_users
FROM users
WHERE email_verified = true
  AND id NOT IN (SELECT user_id FROM business_members WHERE business_id = 'a0000000-0000-4000-8000-000000000001');

