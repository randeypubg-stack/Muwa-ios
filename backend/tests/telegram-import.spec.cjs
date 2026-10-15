const fs = require("node:fs"),
  path = require("node:path");
const { createHash, randomUUID } = require("node:crypto");
const { testPool } = require("./db");
const { adminService } = require("./adminService");
const storage = require("./testStorage");
const root = path.resolve(__dirname, "../..");
const audio = Buffer.alloc(32);
Buffer.from([255, 251, 144, 0]).copy(audio);
const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
const source = {
  channelId: "-1001234567890",
  messageId: 1,
  audioSha256: hash(audio),
};
const metadata = {
  title: "نص",
  artist: "Muwa",
  language: "ar",
  duration: 5,
  status: "draft",
};
const request = (body, user = 1) =>
  adminService.handle(
    new Request("https://muwa-app.floot.app/_api/admin/action", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-fixture-user": String(user),
      },
      body: JSON.stringify(body),
    }),
    "POST",
  );
async function plan(bytes = audio) {
  const r = await request({
    action: "prepare-upload",
    files: [
      { part: "audio", contentType: "audio/mpeg", sizeBytes: bytes.length },
    ],
  });
  expect(r.status).toBe(200);
  const p = await r.json();
  storage.files.set(p.files[0].filename, { bytes, sizeBytes: bytes.length });
  return p;
}
const importTrack = (p, s = source) =>
  request({
    action: "import-telegram-track",
    source: s,
    uploadId: p.uploadId,
    ...metadata,
  });
describe("Telegram import in the existing catalogue", () => {
  it("deduplicates bot forwards against channels without mixing their source namespace or changing curated metadata", async () => {
    const first = await (await importTrack(await plan())).json();
    await testPool.query(
      "UPDATE catalog_tracks SET title='Curated',status='published' WHERE id=$1",
      [first.trackId],
    );
    const botSource = {
      botId: 123456789,
      chatId: 987654321,
      messageId: 1,
      audioSha256: hash(audio),
    };
    const forwarded = await importTrack(await plan(), botSource);
    expect(forwarded.status).toBe(200);
    expect(await forwarded.json()).toEqual({
      ok: true,
      trackId: first.trackId,
      importStatus: "duplicate",
    });
    const replay = await importTrack({ uploadId: randomUUID() }, botSource);
    expect((await replay.json()).trackId).toBe(first.trackId);
    const lookup = await request({
      action: "lookup-telegram-import",
      source: botSource,
    });
    expect((await lookup.json()).trackId).toBe(first.trackId);
    const changed = { ...botSource, audioSha256: "a".repeat(64) };
    expect(
      (await request({ action: "lookup-telegram-import", source: changed }))
        .status,
    ).toBe(409);
    expect(
      (
        await request(
          { action: "lookup-telegram-import", source: botSource },
          3,
        )
      ).status,
    ).toBe(403);
    expect(
      (await testPool.query("SELECT title,status FROM catalog_tracks")).rows,
    ).toEqual([{ title: "Curated", status: "published" }]);
    expect(
      (
        await testPool.query(
          "SELECT count(*)::int AS n FROM catalog_telegram_bot_sources",
        )
      ).rows[0].n,
    ).toBe(1);
  });
  it("does not link old bytes to a track whose audio changed while its row was locked", async () => {
    const originalPlan = await plan();
    const manual = await request({
      action: "save-track",
      uploadId: originalPlan.uploadId,
      ...metadata,
    });
    const id = (await manual.json()).trackId;
    const importPlan = await plan();
    const changed = Buffer.from(audio);
    changed[31] = 8;
    const replacement = await plan(changed);
    const connection = await testPool.connect();
    let pending;
    try {
      await connection.query("BEGIN");
      await connection.query(
        "SELECT id FROM catalog_tracks WHERE id=$1 FOR UPDATE",
        [id],
      );
      pending = importTrack(importPlan);
      let waiting = false;
      for (let n = 0; n < 100; n++) {
        waiting = (
          await testPool.query(
            "SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE '%catalog_audio_fingerprints%') AS waiting",
          )
        ).rows[0].waiting;
        if (waiting) break;
        await new Promise((resolve) => setTimeout(resolve, 10));
      }
      expect(waiting).toBeTrue();
      await connection.query(
        "UPDATE catalog_tracks SET audio_filename=$1,revision=revision+1 WHERE id=$2",
        [replacement.files[0].filename, id],
      );
      await connection.query(
        "UPDATE catalog_audio_fingerprints SET sha256=$1 WHERE track_id=$2",
        [hash(changed), id],
      );
      await connection.query("COMMIT");
    } finally {
      await connection.query("ROLLBACK");
      connection.release();
    }
    const response = await pending;
    expect(response.status).toBe(200);
    expect((await response.json()).trackId).not.toBe(id);
    expect(
      (await testPool.query("SELECT count(*)::int AS n FROM catalog_tracks"))
        .rows[0].n,
    ).toBe(2);
  });
  let restore;
  beforeAll(async () => {
    restore = storage.installFetch();
    await testPool.query(
      "CREATE TABLE IF NOT EXISTS users(id integer PRIMARY KEY); INSERT INTO users(id) VALUES(1),(2),(3) ON CONFLICT DO NOTHING",
    );
    for (const name of [
      "admin-migration.sql",
      "security-migration.sql",
      "telegram-import-migration.sql",
      "telegram-import-migration.sql",
      "asr-migration.sql",
    ])
      await testPool.query(fs.readFileSync(path.join(root, name), "utf8"));
  });
  afterAll(() => restore());
  beforeEach(async () => {
    await testPool.query(
      "TRUNCATE catalog_tracks,catalog_uploads,publication_drafts,admin_audit_events,muwa_request_limits CASCADE",
    );
    storage.files.clear();
  });
  it("requires the verified owner session and cannot auto-publish", async () => {
    expect(
      (await request({ action: "lookup-telegram-import", source }, 0)).status,
    ).toBe(401);
    expect(
      (await request({ action: "lookup-telegram-import", source }, 2)).status,
    ).toBe(403);
    const p = await plan();
    expect(
      (
        await request({
          action: "import-telegram-track",
          source,
          uploadId: p.uploadId,
          ...metadata,
          status: "published",
        })
      ).status,
    ).toBe(400);
    expect(
      (await testPool.query("select count(*)::int as n from catalog_tracks"))
        .rows[0].n,
    ).toBe(0);
  });
  it("denies other administrators, including client claims to own the app", async () => {
    expect(
      (
        await request(
          {
            action: "lookup-telegram-import",
            source,
            ownerId: 1,
            email: "randey.pubg@gmail.com",
          },
          4,
        )
      ).status,
    ).toBe(403);
    expect(
      (
        await request(
          {
            action: "import-telegram-track",
            source,
            uploadId: randomUUID(),
            ...metadata,
          },
          4,
        )
      ).status,
    ).toBe(403);
    expect(
      (
        await testPool.query(
          "select count(*)::int as n from catalog_telegram_sources",
        )
      ).rows[0].n,
    ).toBe(0);
  });
  it("fails closed without configured owner and never consumes an upload", async () => {
    const configured = process.env.MUWA_TELEGRAM_OWNER_ID;
    try {
      delete process.env.MUWA_TELEGRAM_OWNER_ID;
      expect(
        (await request({ action: "lookup-telegram-import", source })).status,
      ).toBe(403);
      expect(
        (
          await request({
            action: "import-telegram-track",
            source,
            uploadId: randomUUID(),
            ...metadata,
          })
        ).status,
      ).toBe(403);
    } finally {
      process.env.MUWA_TELEGRAM_OWNER_ID = configured;
    }
  });
  it("imports one draft and recovers a lost acknowledgement after lease consumption/expiry", async () => {
    const p = await plan(),
      r = await importTrack(p);
    expect(r.status).toBe(200);
    const first = await r.json();
    expect(first.importStatus).toBe("created");
    await testPool.query(
      "update catalog_uploads set expires_at=now()-interval '1 day'",
    );
    const replay = await importTrack(p);
    expect(replay.status).toBe(200);
    expect((await replay.json()).trackId).toBe(first.trackId);
    const lookup = await request({ action: "lookup-telegram-import", source });
    expect((await lookup.json()).trackId).toBe(first.trackId);
    const rows = (await testPool.query("select * from catalog_tracks")).rows;
    expect(rows.length).toBe(1);
    expect(rows[0].status).toBe("draft");
  });
  it("serializes the same source and duplicate bytes from different messages/channels", async () => {
    const p1 = await plan(),
      p2 = await plan(),
      p3 = await plan();
    const responses = await Promise.all([
      importTrack(p1),
      importTrack(p2),
      importTrack(p3, { ...source, channelId: "-1009876543210", messageId: 7 }),
    ]);
    expect(responses.map((r) => r.status)).toEqual([200, 200, 200]);
    const ids = await Promise.all(responses.map((r) => r.json()));
    expect(new Set(ids.map((x) => x.trackId)).size).toBe(1);
    expect(
      (await testPool.query("select count(*)::int as n from catalog_tracks"))
        .rows[0].n,
    ).toBe(1);
    expect(
      (
        await testPool.query(
          "select count(*)::int as n from catalog_telegram_sources",
        )
      ).rows[0].n,
    ).toBe(2);
  });
  it("verifies file bytes instead of trusting the claimed hash; a changed source cannot overwrite curated metadata", async () => {
    const p = await plan();
    expect(
      (await importTrack(p, { ...source, audioSha256: "a".repeat(64) })).status,
    ).toBe(409);
    const first = await (await importTrack(p)).json();
    await testPool.query(
      "update catalog_tracks set title='Curated',status='published' where id=$1",
      [first.trackId],
    );
    const changed = Buffer.from(audio);
    changed[31] = 7;
    const replacement = await plan(changed);
    expect(
      (
        await importTrack(replacement, {
          ...source,
          audioSha256: hash(changed),
        })
      ).status,
    ).toBe(409);
    expect(
      (await testPool.query("select title from catalog_tracks")).rows[0].title,
    ).toBe("Curated");
    // A real different recording with the same title must not be discarded.
    expect(
      (
        await importTrack(replacement, {
          ...source,
          messageId: 2,
          audioSha256: hash(changed),
        })
      ).status,
    ).toBe(200);
    expect(
      (await testPool.query("select count(*)::int as n from catalog_tracks"))
        .rows[0].n,
    ).toBe(2);
  });
  it("deduplicates against a normal catalogue upload and preserves its status/edits", async () => {
    const p = await plan();
    const manual = await request({
      action: "save-track",
      uploadId: p.uploadId,
      ...metadata,
      title: "Owner title",
      status: "published",
    });
    const id = (await manual.json()).trackId;
    const imported = await importTrack(await plan());
    expect(imported.status).toBe(200);
    expect(await imported.json()).toEqual({
      ok: true,
      trackId: id,
      importStatus: "duplicate",
    });
    const row = (
      await testPool.query("select title,status from catalog_tracks")
    ).rows[0];
    expect(row).toEqual({ title: "Owner title", status: "published" });
  });
});
