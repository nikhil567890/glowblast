-- 007_add_consent_category_and_metadata.sql

-- 1. Safely add consent_category and consent_text_version columns to customer_consent
ALTER TABLE public.customer_consent
    ADD COLUMN IF NOT EXISTS consent_category VARCHAR(32),
    ADD COLUMN IF NOT EXISTS consent_text_version VARCHAR(64);

-- Set any unclassified, null, or historical default records to 'unclassified'.
-- Historical records created prior to category-specific provenance (lacking consent_text_version
-- or created under legacy defaults) must not be assumed to have verified marketing/utility consent.
UPDATE public.customer_consent
SET consent_category = 'unclassified'
WHERE consent_category IS NULL
   OR consent_category = 'unclassified'
   OR (consent_text_version IS NULL AND source IN ('legacy', 'migration', 'seed', 'manual_seed', 'default'));

ALTER TABLE public.customer_consent
    ALTER COLUMN consent_category SET DEFAULT 'unclassified',
    ALTER COLUMN consent_category SET NOT NULL;

-- 2. Safely add columns to consent_audit_log
ALTER TABLE public.consent_audit_log
    ADD COLUMN IF NOT EXISTS consent_category VARCHAR(32),
    ADD COLUMN IF NOT EXISTS customer_id VARCHAR(64),
    ADD COLUMN IF NOT EXISTS consent_text_version VARCHAR(64);

UPDATE public.consent_audit_log
SET consent_category = 'unclassified'
WHERE consent_category IS NULL
   OR consent_category = 'unclassified'
   OR (consent_text_version IS NULL AND source IN ('legacy', 'migration', 'seed', 'manual_seed', 'default'));

ALTER TABLE public.consent_audit_log
    ALTER COLUMN consent_category SET DEFAULT 'unclassified',
    ALTER COLUMN consent_category SET NOT NULL;

-- 3. Ensure valid categories check constraints allowing ('marketing', 'utility', 'unclassified')
-- Scoped strictly to public.customer_consent and public.consent_audit_log
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.customer_consent'::regclass
          AND conname = 'chk_customer_consent_category'
    ) THEN
        ALTER TABLE public.customer_consent DROP CONSTRAINT chk_customer_consent_category;
    END IF;

    ALTER TABLE public.customer_consent
        ADD CONSTRAINT chk_customer_consent_category CHECK (consent_category IN ('marketing', 'utility', 'unclassified'));
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.consent_audit_log'::regclass
          AND conname = 'chk_consent_audit_category'
    ) THEN
        ALTER TABLE public.consent_audit_log DROP CONSTRAINT chk_consent_audit_category;
    END IF;

    ALTER TABLE public.consent_audit_log
        ADD CONSTRAINT chk_consent_audit_category CHECK (consent_category IN ('marketing', 'utility', 'unclassified'));
END $$;

-- 4. Safely inspect and adjust primary key to (normalized_phone, consent_category)
-- - Verifies exact existing PK columns (not just presence of a column).
-- - Handles legacy ['normalized_phone'] and composite ['normalized_phone', 'consent_category'].
-- - NEVER automatically deletes duplicate rows using ctid or any other destructive method.
-- - Aborts safely if duplicates exist, providing the exact preflight query.
DO $$
DECLARE
    pk_name TEXT;
    pk_cols TEXT[];
    dup_count INT := 0;
BEGIN
    SELECT c.conname, ARRAY_AGG(a.attname ORDER BY array_position(c.conkey, a.attnum))
    INTO pk_name, pk_cols
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
    WHERE c.conrelid = 'public.customer_consent'::regclass
      AND c.contype = 'p'
    GROUP BY c.conname;

    -- If PK is already the exact composite key, no action needed
    IF pk_cols = ARRAY['normalized_phone', 'consent_category'] THEN
        RAISE NOTICE 'Primary key on customer_consent is already composite (normalized_phone, consent_category). No action needed.';
        RETURN;
    END IF;

    -- Verify no duplicates exist before altering PK (do not delete data automatically!)
    SELECT COUNT(*) INTO dup_count
    FROM (
        SELECT normalized_phone, consent_category
        FROM public.customer_consent
        GROUP BY normalized_phone, consent_category
        HAVING COUNT(*) > 1
    ) dups;

    IF dup_count > 0 THEN
        RAISE EXCEPTION 'Migration 007 aborted: % conflicting duplicate group(s) found on customer_consent(normalized_phone, consent_category). Automatic deletion is disabled to preserve data integrity. Run preflight query: SELECT normalized_phone, consent_category, count(*), array_agg(status) AS statuses, array_agg(recorded_at) AS recorded_timestamps FROM customer_consent GROUP BY normalized_phone, consent_category HAVING count(*) > 1;', dup_count;
    END IF;

    IF pk_name IS NOT NULL THEN
        RAISE NOTICE 'Dropping existing primary key constraint % with columns %', pk_name, pk_cols;
        EXECUTE 'ALTER TABLE public.customer_consent DROP CONSTRAINT ' || quote_ident(pk_name);
    END IF;

    ALTER TABLE public.customer_consent ADD PRIMARY KEY (normalized_phone, consent_category);
    RAISE NOTICE 'Established composite primary key (normalized_phone, consent_category) on public.customer_consent';
END $$;

-- 5. Add performance indexes for category and status lookups
CREATE INDEX IF NOT EXISTS idx_customer_consent_phone_cat ON public.customer_consent (normalized_phone, consent_category);
CREATE INDEX IF NOT EXISTS idx_customer_consent_status_cat ON public.customer_consent (status, consent_category);
CREATE INDEX IF NOT EXISTS idx_consent_audit_phone_cat ON public.consent_audit_log (normalized_phone, consent_category, created_at DESC);

-- 6. Preserve and enforce foreign key integrity for customer_id
-- Preserves all data without nulling out customer_id.
-- If unresolvable orphans exist, aborts safely with preflight diagnostic.
DO $$
DECLARE
    orphan_count INT := 0;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.customer_consent'::regclass
          AND conname = 'customer_consent_customer_id_fkey'
    ) THEN
        -- Preserve data: populate missing customer records where phone does not collide
        INSERT INTO public.customers (id, normalized_phone, display_name, created_at, updated_at)
        SELECT DISTINCT c.customer_id, c.normalized_phone, c.customer_id, NOW(), NOW()
        FROM public.customer_consent c
        WHERE c.customer_id IS NOT NULL
          AND c.customer_id NOT IN (SELECT id FROM public.customers)
          AND c.normalized_phone NOT IN (SELECT normalized_phone FROM public.customers)
        ON CONFLICT (id) DO NOTHING;

        -- Verify if any orphaned customer_id records remain
        SELECT COUNT(*) INTO orphan_count
        FROM public.customer_consent
        WHERE customer_id IS NOT NULL
          AND customer_id NOT IN (SELECT id FROM public.customers);

        IF orphan_count > 0 THEN
            RAISE EXCEPTION 'Migration 007 aborted: % customer_consent record(s) contain customer_id values not present in customers table. Cannot add foreign key constraint without data loss. Run preflight query: SELECT c.normalized_phone, c.customer_id, c.recorded_at FROM customer_consent c LEFT JOIN customers cust ON c.customer_id = cust.id WHERE c.customer_id IS NOT NULL AND cust.id IS NULL;', orphan_count;
        END IF;

        ALTER TABLE public.customer_consent
            ADD CONSTRAINT customer_consent_customer_id_fkey
            FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;
        RAISE NOTICE 'Added foreign key constraint customer_consent_customer_id_fkey';
    END IF;
END $$;
