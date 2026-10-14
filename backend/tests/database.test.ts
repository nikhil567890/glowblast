process.env.NODE_ENV = 'test';
import test from 'node:test';
import assert from 'node:assert/strict';
import { getSanitizedEndpointInfo, checkDevelopmentDatabaseConnection } from '../src/db/connectionCheck';
import { env } from '../src/config/env';

test('Database Connection & Security Suite', async (t) => {
  await t.test('getSanitizedEndpointInfo strips credentials cleanly', () => {
    const fakeUrl = 'postgresql://admin_user:super_secret_pw123@ep-cool-branch-12345.us-east-2.aws.neon.tech/neondb?sslmode=require';
    const info = getSanitizedEndpointInfo(fakeUrl);
    assert.strictEqual(info.host, 'ep-cool-branch-12345.us-east-2.aws.neon.tech');
    assert.strictEqual(info.database, 'neondb');
    // Ensure credentials never leak into info object
    const serialized = JSON.stringify(info);
    assert.strictEqual(serialized.includes('admin_user'), false);
    assert.strictEqual(serialized.includes('super_secret_pw123'), false);
  });

  await t.test('checkDevelopmentDatabaseConnection handles missing URL cleanly', async () => {
    const result = await checkDevelopmentDatabaseConnection('');
    assert.strictEqual(result.success, false);
    assert.strictEqual(typeof result.sanitizedError, 'string');
    assert.match(result.sanitizedError!, /missing|No database URL/i);
  });

  if (env.TEST_DATABASE_URL) {
    await t.test('Live Neon PostgreSQL development check executes SELECT 1 and closes cleanly', async () => {
      const result = await checkDevelopmentDatabaseConnection();

      // Ensure no secrets exist in the result object
      const resultJson = JSON.stringify(result);
      assert.strictEqual(resultJson.includes('password'), false);
      assert.strictEqual(resultJson.includes('postgres://'), false);
      assert.strictEqual(resultJson.includes('postgresql://'), false);

      assert.strictEqual(result.success, true, `Connection failed: ${result.sanitizedError}`);
      assert.strictEqual(result.queryResult, 1, 'Expected SELECT 1 result to equal 1');
      assert.strictEqual(typeof result.endpoint, 'string');
      assert.ok(result.endpoint!.includes('neon.tech'), 'Expected Neon endpoint host');
      assert.ok(typeof result.durationMs === 'number' && result.durationMs! > 0);
    });
  }
});
