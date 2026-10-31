-- Migration 012: Seed the initial business and backfill all existing data
-- The existing production spa becomes the first business account.
-- All historical data is assigned to this business with a stable, deterministic UUID.
-- This preserves every customer, campaign, consent record, template, reservation, and message.
--
-- Safety Guarantees:
-- 1. Idempotent: Can be safely re-run without duplicating records or corrupting state.
-- 2. Owner Verification: Does NOT blindly guess the owner if multiple verified users exist.
--    If ambiguous, it halts safely and requires explicit confirmation.
-- 3. Non-destructive: Does NOT delete or alter any customer or campaign records.

DO $$
DECLARE
  v_initial_biz_id CONSTANT UUID := 'a0000000-0000-4000-8000-000000000001';
  v_total_users    INT;
  v_verified_users INT;
  v_target_email   TEXT;
  v_owner_id       VARCHAR(64);
  v_owner_name     VARCHAR(255);
  v_owner_email    VARCHAR(255);
  v_biz_name       VARCHAR(255);
  v_owner_phone    VARCHAR(32);
  v_biz_id         UUID;
  v_cust_count     INT := 0;
  v_camp_count     INT := 0;
BEGIN
  -- 1. Check if the initial business already exists (idempotent re-run safety)
  SELECT id INTO v_biz_id
  FROM businesses
  WHERE id = v_initial_biz_id;

  IF v_biz_id IS NULL THEN
    -- Check total and verified user counts
    SELECT COUNT(*) INTO v_total_users FROM users;
    SELECT COUNT(*) INTO v_verified_users FROM users WHERE email_verified = true;

    -- If no users exist, skip backfill safely (clean test DB or fresh install)
    IF v_total_users = 0 THEN
      RAISE NOTICE '[Backfill] No users found in database — skipping backfill for fresh install.';
      RETURN;
    END IF;

    -- Check if an explicit owner email was provided via session setting
    BEGIN
      v_target_email := NULLIF(TRIM(current_setting('glowblast.initial_owner_email', true)), '');
    EXCEPTION WHEN OTHERS THEN
      v_target_email := NULL;
    END;

    IF v_target_email IS NOT NULL THEN
      -- Use explicitly designated owner
      SELECT id, name, email, COALESCE(NULLIF(business_name, ''), 'GlowBlast Spa & Wellness'), phone
      INTO v_owner_id, v_owner_name, v_owner_email, v_biz_name, v_owner_phone
      FROM users
      WHERE LOWER(email) = LOWER(v_target_email) AND email_verified = true;

      IF v_owner_id IS NULL THEN
        RAISE EXCEPTION '[Backfill] Specified glowblast.initial_owner_email does not match any verified user in users table.';
      END IF;
      RAISE NOTICE '[Backfill] Using explicitly specified initial business owner.';

    ELSIF v_verified_users = 1 THEN
      -- Exactly one verified user exists — unambiguous sole owner
      SELECT id, name, email, COALESCE(NULLIF(business_name, ''), 'GlowBlast Spa & Wellness'), phone
      INTO v_owner_id, v_owner_name, v_owner_email, v_biz_name, v_owner_phone
      FROM users
      WHERE email_verified = true;

      RAISE NOTICE '[Backfill] Unambiguous verified single owner identified.';

    ELSIF v_verified_users = 0 AND v_total_users = 1 THEN
      -- Exactly one user exists in total (even if not yet marked email_verified)
      SELECT id, name, email, COALESCE(NULLIF(business_name, ''), 'GlowBlast Spa & Wellness'), phone
      INTO v_owner_id, v_owner_name, v_owner_email, v_biz_name, v_owner_phone
      FROM users;

      RAISE NOTICE '[Backfill] Single registered user identified as initial owner.';

    ELSE
      -- Multiple verified users exist without explicit owner designation.
      -- Abort safely rather than guessing incorrectly!
      RAISE EXCEPTION '[Backfill] Ambiguous business owner: Found % verified users and % total users. Cannot automatically infer the initial business owner without risking assigning ownership to the wrong account. To proceed, execute: SET glowblast.initial_owner_email = ''verified_owner@example.com''; before running this migration.', v_verified_users, v_total_users;
    END IF;

    -- 2. Create the initial business with deterministic stable UUID
    INSERT INTO businesses (
      id,
      slug,
      display_name,
      owner_user_id,
      phone,
      email,
      production_enabled
    ) VALUES (
      v_initial_biz_id,
      'initial-spa',
      v_biz_name,
      v_owner_id,
      v_owner_phone,
      v_owner_email,
      true  -- Existing production spa retains production messaging rights
    )
    ON CONFLICT (id) DO UPDATE
    SET display_name = EXCLUDED.display_name,
        owner_user_id = EXCLUDED.owner_user_id,
        updated_at = NOW()
    RETURNING id INTO v_biz_id;

    RAISE NOTICE '[Backfill] Initial business created with stable ID: %', v_biz_id;
  ELSE
    RAISE NOTICE '[Backfill] Initial business % already exists. Preserving existing record.', v_biz_id;
    -- Retrieve owner_user_id for membership check
    SELECT owner_user_id INTO v_owner_id FROM businesses WHERE id = v_biz_id;
  END IF;

  -- 3. Create or ensure owner membership (idempotent)
  IF v_owner_id IS NOT NULL THEN
    INSERT INTO business_members (business_id, user_id, role)
    VALUES (v_biz_id, v_owner_id, 'owner')
    ON CONFLICT (business_id, user_id) DO NOTHING;
  END IF;

  -- 3b. Backfill existing verified users as staff members of the initial business
  -- Any existing verified user registered in the single-spa production database
  -- belongs to the original spa team and receives 'staff' membership so they are not locked out.
  INSERT INTO business_members (business_id, user_id, role)
  SELECT v_biz_id, id, 'staff'
  FROM users
  WHERE id != v_owner_id AND email_verified = true
  ON CONFLICT (business_id, user_id) DO NOTHING;

  -- 4. Backfill all tenant-scoped data tables (only unassigned rows)
  UPDATE customers SET business_id = v_biz_id WHERE business_id IS NULL;
  GET DIAGNOSTICS v_cust_count = ROW_COUNT;

  UPDATE customer_consent SET business_id = v_biz_id WHERE business_id IS NULL;
  UPDATE consent_audit_log SET business_id = v_biz_id WHERE business_id IS NULL;

  UPDATE campaigns SET business_id = v_biz_id WHERE business_id IS NULL;
  GET DIAGNOSTICS v_camp_count = ROW_COUNT;

  UPDATE campaign_messages SET business_id = v_biz_id WHERE business_id IS NULL;
  UPDATE whatsapp_templates SET business_id = v_biz_id WHERE business_id IS NULL;
  UPDATE webhook_events SET business_id = v_biz_id WHERE business_id IS NULL;
  UPDATE recipient_reservations SET business_id = v_biz_id WHERE business_id IS NULL;

  RAISE NOTICE '[Backfill] Complete! Assigned % customers and % campaigns to initial business %',
    v_cust_count, v_camp_count, v_biz_id;
END $$;
