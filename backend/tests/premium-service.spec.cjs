const fs = require('node:fs');
const path = require('node:path');
const {testPool, db} = require('./db');
const {premiumService} = require('./premiumService');
const root = path.resolve(__dirname, '../..');

function request(user, body, origin) {
  const headers = {'Content-Type': 'application/json', 'x-fixture-user': String(user)};
  if (origin) headers.Origin = origin;
  return premiumService.handle(new Request('https://muwa-app.floot.app/_api/premium/access', {
    method: 'POST', headers, body: JSON.stringify(body)
  }), {safeParse: value => ({success: true, data: value})});
}
async function create(maxUses = 1) {
  const response = await request(1, {action: 'create', label: 'Fixture', durationDays: 7, maxUses, validDays: 30});
  expect(response.status).toBe(200);
  return response.json();
}

describe('Premium transactions on a disposable PostgreSQL database', () => {
  beforeAll(async () => {
    // This suite targets only the explicitly configured disposable fixture DB.
    await testPool.query('CREATE TABLE IF NOT EXISTS users (id integer PRIMARY KEY); INSERT INTO users VALUES (1),(2),(3) ON CONFLICT DO NOTHING');
    await testPool.query(fs.readFileSync(path.join(root, 'premium-migration.sql'), 'utf8'));
    await testPool.query(fs.readFileSync(path.join(root, 'migration.sql'), 'utf8'));
    await testPool.query(fs.readFileSync(path.join(root, 'premium-migration.sql'), 'utf8'));
  });
  beforeEach(async () => {
    await testPool.query('TRUNCATE premium_redemptions, premium_code_limits, premium_codes, premium_access, premium_code_admins');
    await testPool.query('INSERT INTO premium_code_admins(user_id) VALUES (1)');
  });


  it('enforces 50 creations per hour under concurrent requests', async () => {
    const responses = await Promise.all(Array.from({length: 60}, () => request(1,
      {action: 'create', label: 'Concurrent', durationDays: 7, maxUses: 1, validDays: 30})));
    expect(responses.filter(r => r.status === 200).length).toBe(50);
    expect(responses.filter(r => r.status === 429).length).toBe(10);
    expect(Number((await testPool.query('SELECT count(*) FROM premium_codes')).rows[0].count)).toBe(50);
  });
  it('grants the last activation to only one account', async () => {
    const value = await create();
    const responses = await Promise.all([2,3].map(user => request(user, {action: 'redeem', code: value.code})));
    expect(responses.map(r => r.status).sort()).toEqual([200,400]);
    expect(Number((await testPool.query('SELECT count(*) FROM premium_redemptions')).rows[0].count)).toBe(1);
    expect((await testPool.query('SELECT uses FROM premium_codes')).rows[0].uses).toBe(1);
  });
  it('does not extend access twice on repeated redemption', async () => {
    const value = await create(2);
    const first = await (await request(2, {action: 'redeem', code: value.code})).json();
    const repeated = await (await request(2, {action: 'redeem', code: value.code})).json();
    expect(repeated.alreadyRedeemed).toBeTrue();
    expect(repeated.expiresAt).toBe(first.expiresAt);
    expect((await testPool.query('SELECT uses FROM premium_codes')).rows[0].uses).toBe(1);
  });
  it('disabling a code preserves previously granted access', async () => {
    const value = await create(2);
    expect((await request(2, {action: 'redeem', code: value.code})).status).toBe(200);
    const id = (await testPool.query('SELECT id FROM premium_codes')).rows[0].id;
    expect((await request(1, {action: 'disable', id})).status).toBe(200);
    expect((await (await request(2, {action: 'status'})).json()).isPremium).toBeTrue();
    expect((await request(3, {action: 'redeem', code: value.code})).status).toBe(400);
  });
  it('counts unsuccessful activation attempts towards the rate limit', async () => {
    for (let i=0; i<20; i++) expect((await request(2, {action: 'redeem', code: 'INVALID'})).status).toBe(400);
    expect((await request(2, {action: 'redeem', code: 'INVALID'})).status).toBe(429);
  });
  it('does not consume a gift for an account with permanent access', async () => {
    const value = await create();
    await testPool.query('INSERT INTO premium_access(user_id, expires_at) VALUES (2, NULL)');
    expect((await request(2, {action: 'redeem', code: value.code})).status).toBe(409);
    expect((await testPool.query('SELECT uses FROM premium_codes')).rows[0].uses).toBe(0);
  });
  it('rejects unauthenticated, unauthorized and foreign-origin mutations', async () => {
    expect((await request(0, {action: 'status'})).status).toBe(401);
    expect((await request(2, {action: 'create'})).status).toBe(403);
    expect((await request(1, {action: 'create'}, 'https://example.com')).status).toBe(403);
  });
});
