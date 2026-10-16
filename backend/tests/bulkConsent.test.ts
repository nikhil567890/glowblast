import { test, describe, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { consentStore } from '../src/store/consentStore';
import { getPool, closePool } from '../src/db/pool';

describe('Bulk WhatsApp Consent Recording & Idempotency Controls', () => {
  beforeEach(async () => {
    const pool = getPool();
    await pool.query("DELETE FROM customers WHERE id LIKE 'cust_bulk_%' OR id LIKE 'cust_optout_%' OR id LIKE 'cust_valid_%' OR id = 'cust_98' OR id = 'cust_99';");
    await pool.query("DELETE FROM customer_consent WHERE normalized_phone LIKE '919876%';");
    await pool.query("DELETE FROM consent_audit_log WHERE normalized_phone LIKE '919876%';");
  });

  after(async () => {
    await closePool();
  });

  test('1. 205 customers recorded in bulk in a single efficient transaction', async () => {
    const records = [];
    for (let i = 1; i <= 205; i++) {
      const padded = i.toString().padStart(6, '0');
      records.push({
        phone: `919876${padded}`,
        customerId: `cust_bulk_${i}`,
        consentCategory: 'marketing' as const,
        status: 'opted_in' as const,
        source: 'Front Desk In-Person Verbal',
        evidence: `Customer verbally consented at reception during booking #${i}`,
        consentTextVersion: 'v2026.1_verbal_confirmed',
      });
    }

    const startTime = Date.now();
    const outcome = await consentStore.bulkRecordConsent({
      records,
      updatedBy: 'receptionist@glowblast.com',
      isAuthorizedAdmin: true,
      allowOptOutOverride: false,
    });
    const durationMs = Date.now() - startTime;

    // Fast execution verification (< 15 seconds for all 205 records over cloud DB connection vs 10+ minutes before)
    console.log(`[Test] Bulk recording 205 customers took ${durationMs}ms`);
    assert.ok(durationMs < 15000, `Expected 205 bulk records to take < 15000ms, took ${durationMs}ms`);

    assert.equal(outcome.totalRequested, 205);
    assert.equal(outcome.succeeded, 205);
    assert.equal(outcome.failed, 0);
    assert.equal(outcome.failures.length, 0);
    assert.equal(outcome.results.length, 205);

    // Verify all returned results report success and correct data
    for (let i = 0; i < 205; i++) {
      const res = outcome.results[i];
      assert.equal(res.success, true);
      assert.equal(res.customerId, `cust_bulk_${i + 1}`);
      assert.equal(res.status, 'opted_in');
      assert.equal(res.consentCategory, 'marketing');
      assert.ok(res.recordedAt);
    }

    // Verify database table has exactly 205 rows
    const pool = getPool();
    const consentCountRes = await pool.query<{ count: string }>(
      `SELECT count(*) FROM customer_consent WHERE consent_category = 'marketing' AND normalized_phone LIKE '919876%';`
    );
    assert.equal(parseInt(consentCountRes.rows[0].count, 10), 205);

    // Verify audit log has 205 initial_opt_in records
    const auditCountRes = await pool.query<{ count: string }>(
      `SELECT count(*) FROM consent_audit_log WHERE action = 'initial_opt_in' AND normalized_phone LIKE '919876%';`
    );
    assert.equal(parseInt(auditCountRes.rows[0].count, 10), 205);
  });

  test('2. Duplicate submission is idempotent: does not duplicate audit log entries', async () => {
    const records = [];
    for (let i = 1; i <= 205; i++) {
      const padded = i.toString().padStart(6, '0');
      records.push({
        phone: `919876${padded}`,
        customerId: `cust_bulk_${i}`,
        source: 'Front Desk In-Person Verbal',
        evidence: `Customer verbally consented at reception during booking #${i}`,
        consentTextVersion: 'v2026.1_verbal_confirmed',
      });
    }

    // First bulk submission
    const firstOutcome = await consentStore.bulkRecordConsent({
      records,
      updatedBy: 'receptionist@glowblast.com',
      isAuthorizedAdmin: true,
      allowOptOutOverride: false,
    });
    assert.equal(firstOutcome.succeeded, 205);

    const pool = getPool();
    const firstAuditCount = await pool.query<{ count: string }>(
      `SELECT count(*) FROM consent_audit_log WHERE normalized_phone LIKE '919876%';`
    );
    assert.equal(parseInt(firstAuditCount.rows[0].count, 10), 205);

    // Second bulk submission (simulating duplicate button press, retry, or re-run)
    const secondOutcome = await consentStore.bulkRecordConsent({
      records,
      updatedBy: 'receptionist@glowblast.com',
      isAuthorizedAdmin: true,
      allowOptOutOverride: false,
    });

    assert.equal(secondOutcome.totalRequested, 205);
    assert.equal(secondOutcome.succeeded, 205);
    assert.equal(secondOutcome.failed, 0);

    // All records report idempotent success
    for (const res of secondOutcome.results) {
      assert.equal(res.success, true);
      assert.equal(res.isDuplicateOrUnchanged, true);
    }

    // Audit log count MUST remain exactly 205 — NO duplicate rows written!
    const secondAuditCount = await pool.query<{ count: string }>(
      `SELECT count(*) FROM consent_audit_log WHERE normalized_phone LIKE '919876%';`
    );
    assert.equal(parseInt(secondAuditCount.rows[0].count, 10), 205);
  });

  test('3. Bulk consent strictly preserves existing opt-outs when allowOptOutOverride is false', async () => {
    // Customer 1 opts out
    await consentStore.recordOptOut({
      phone: '919876900001',
      customerId: 'cust_optout_1',
      source: 'SMS STOP',
      reason: 'Customer requested opt-out via WhatsApp STOP',
      updatedBy: 'system_webhook',
    });

    // Attempt bulk recording for 3 customers: cust_1 (opted out), cust_2 (new), cust_3 (new)
    const outcome = await consentStore.bulkRecordConsent({
      records: [
        {
          phone: '919876900001',
          customerId: 'cust_optout_1',
          source: 'Verbal claim',
          evidence: 'Front desk attempt',
        },
        {
          phone: '919876900002',
          customerId: 'cust_valid_2',
          source: 'Verbal Front Desk',
          evidence: 'In-person check-in',
        },
        {
          phone: '919876900003',
          customerId: 'cust_valid_3',
          source: 'Verbal Front Desk',
          evidence: 'In-person check-in',
        },
      ],
      updatedBy: 'staff@glowblast.com',
      isAuthorizedAdmin: false,
      allowOptOutOverride: false,
    });

    assert.equal(outcome.totalRequested, 3);
    assert.equal(outcome.succeeded, 2);
    assert.equal(outcome.failed, 1);
    assert.equal(outcome.failures.length, 1);
    assert.equal(outcome.failures[0].customerId, 'cust_optout_1');

    // Verify Customer 1 in database is STILL opted_out
    const cust1 = await consentStore.getConsent('919876900001', 'marketing');
    assert.ok(cust1);
    assert.equal(cust1.status, 'opted_out');
    assert.equal(await consentStore.hasActiveConsent('919876900001', 'marketing'), false);

    // Verify Customer 2 and 3 succeeded
    const cust2 = await consentStore.getConsent('919876900002', 'marketing');
    assert.ok(cust2);
    assert.equal(cust2.status, 'opted_in');
  });

  test('4. Partial failure reporting: invalid phones and rejected records reported per customer', async () => {
    const outcome = await consentStore.bulkRecordConsent({
      records: [
        {
          phone: '919876000010',
          customerId: 'cust_valid_10',
          source: 'Verbal',
          evidence: 'Evidence valid',
        },
        {
          phone: '12345', // Invalid phone format
          customerId: 'cust_invalid_phone',
          source: 'Verbal',
          evidence: 'Evidence invalid',
        },
        {
          phone: '919876000011',
          customerId: 'cust_valid_11',
          source: 'Verbal',
          evidence: 'Evidence valid',
        },
      ],
      updatedBy: 'staff@glowblast.com',
      isAuthorizedAdmin: true,
      allowOptOutOverride: false,
    });

    assert.equal(outcome.totalRequested, 3);
    assert.equal(outcome.succeeded, 2);
    assert.equal(outcome.failed, 1);
    assert.equal(outcome.results[0].success, true);
    assert.equal(outcome.results[1].success, false);
    assert.equal(outcome.results[1].error, 'Invalid WhatsApp phone format');
    assert.equal(outcome.results[2].success, true);
  });

  test('5. Retrying only failed customers succeeds without duplicate writes on existing customers', async () => {
    // Seed 1 opted-out customer
    await consentStore.recordOptOut({
      phone: '919876000099',
      customerId: 'cust_99',
      source: 'User request',
      updatedBy: 'admin',
    });

    // Run batch with 1 valid and 1 opted-out
    const batch1 = await consentStore.bulkRecordConsent({
      records: [
        { phone: '919876000098', customerId: 'cust_98', source: 'Verbal', evidence: 'Desk 1' },
        { phone: '919876000099', customerId: 'cust_99', source: 'Verbal', evidence: 'Desk 2' },
      ],
      updatedBy: 'staff@glowblast.com',
      allowOptOutOverride: false,
    });

    assert.equal(batch1.succeeded, 1);
    assert.equal(batch1.failed, 1);

    // Only retry the failed customer (cust_99) with authorized admin and override
    const retryBatch = await consentStore.bulkRecordConsent({
      records: [
        { phone: '919876000099', customerId: 'cust_99', source: 'Signed Paper Waiver', evidence: 'Waiver #99 signed in person' },
      ],
      updatedBy: 'admin@glowblast.com',
      isAuthorizedAdmin: true,
      allowOptOutOverride: true,
    });

    assert.equal(retryBatch.succeeded, 1);
    assert.equal(retryBatch.failed, 0);

    const cust99 = await consentStore.getConsent('919876000099', 'marketing');
    assert.equal(cust99?.status, 'opted_in');
  });
});
