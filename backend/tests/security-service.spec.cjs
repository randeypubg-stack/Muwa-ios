const fs = require("node:fs"),
  path = require("node:path");
const { randomUUID, createHash } = require("node:crypto");
const superjson = require("superjson").default;
const { db, testPool } = require("./db");
const {
  reservePublication,
  takeRateLimit,
  uploadPolicy,
} = require("./uploadSecurity");
const {
  checkMediaHeader,
  catalogueMediaURL,
  MediaHeaderProbe,
} = require("./mediaSecurity");
const { adminService } = require("./adminService");
const publication = require("../endpoints/publicationUpload_POST");
const media = require("../endpoints/catalog/media_GET");
const diagnostics = require("../endpoints/diagnostics/events_POST");
const storage = require("./testStorage");
const root = path.resolve(__dirname, "../..");
const sha = (b) => createHash("sha256").update(b).digest("hex");
const audio = Buffer.alloc(32);
Buffer.from([255, 251, 144, 0]).copy(audio);
const post = (path, user, body) =>
  new Request(`https://muwa-app.floot.app/_api/${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-fixture-user": String(user),
    },
    body: JSON.stringify(body),
  });
const admin = (body, user = 1) =>
  adminService.handle(post("admin/action", user, body), "POST");
const getMedia = (url, user = 0) =>
  media.handle(
    new Request(url, {
      headers: { "x-fixture-user": String(user), Range: "bytes=0-15" },
    }),
  );
const meta = {
  title: "Fixture",
  artist: "Muwa",
  language: "ar",
  duration: 10,
  status: "draft",
};
async function prepared() {
  const r = await admin({
    action: "prepare-upload",
    files: [{ part: "audio", contentType: "audio/mpeg", sizeBytes: 32 }],
  });
  expect(r.status).toBe(200);
  const p = await r.json();
  storage.files.set(p.files[0].filename, { sizeBytes: 32, bytes: audio });
  return p;
}
async function publicationPart(id, part, bytes = audio) {
  const input = {
    draftId: id,
    part,
    originalName: part === "submission" ? "submission.json" : "audio.mp3",
    contentType: part === "submission" ? "application/json" : "audio/mpeg",
    sizeBytes: bytes.length,
    sha256: sha(bytes),
  };
  const r = await publication.handle(
    post("publicationUpload", 2, { json: input }),
  );
  expect(r.status).toBe(200);
  const result = superjson.parse(await r.text());
  if (!result.alreadyUploaded)
    storage.files.set(result.storageKey, { sizeBytes: bytes.length, bytes });
  return { input, result };
}
describe("Muwa security boundaries with disposable PostgreSQL", () => {
  let restoreFetch;
  beforeAll(async () => {
    restoreFetch = storage.installFetch();
    await testPool.query(
      "CREATE TABLE IF NOT EXISTS users(id integer PRIMARY KEY); ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name text; INSERT INTO users(id) VALUES(1),(2),(3) ON CONFLICT DO NOTHING",
    );
    for (const name of [
      "admin-migration.sql",
      "security-migration.sql",
      "security-migration.sql",
      "telegram-import-migration.sql",
      "asr-migration.sql",
    ])
      await testPool.query(fs.readFileSync(path.join(root, name), "utf8"));
  });
  afterAll(() => restoreFetch());
  beforeEach(async () => {
    await testPool.query(
      "TRUNCATE admin_audit_events,publication_drafts,catalog_uploads,catalog_tracks,muwa_request_limits,muwa_diagnostics CASCADE",
    );
    storage.files.clear();
    storage.puts.length = 0;
  });
  it("serializes concurrent reservations so six uploads cannot exceed five active drafts", async () => {
    const results = await Promise.allSettled(
      Array.from({ length: 6 }, () =>
        reservePublication(2, false, {
          draftId: randomUUID(),
          part: "audio",
          contentType: "audio/mpeg",
          sizeBytes: 32,
        }),
      ),
    );
    expect(results.filter((r) => r.status === "fulfilled").length).toBe(5);
    expect(
      results
        .filter((r) => r.status === "rejected")
        .map((r) => r.reason.status),
    ).toEqual([429]);
    expect(
      Number(
        (await testPool.query("SELECT count(*) FROM publication_drafts"))
          .rows[0].count,
      ),
    ).toBe(5);
  });
  it("atomically claims daily bytes; concurrent reservations cannot spend the same remaining capacity", async () => {
    const id = randomUUID();
    await testPool.query(
      "INSERT INTO publication_drafts(id,user_id) VALUES($1,2)",
      [id],
    );
    for (let i = 0; i < 6; i++)
      await testPool.query(
        "INSERT INTO publication_uploads(id,draft_id,user_id,part,filename,content_type,size_bytes,expires_at) VALUES($1,$2,2,'audio',$3,'audio/mpeg',$4,now())",
        [
          randomUUID(),
          id,
          `publications/${id}/audio-${randomUUID()}.mp3`,
          (i < 5 ? 100 : 10) * 1024 * 1024,
        ],
      );
    const result = await Promise.allSettled(
      [1, 2].map(() =>
        reservePublication(2, false, {
          draftId: id,
          part: "audio",
          contentType: "audio/mpeg",
          sizeBytes: 2 * 1024 * 1024,
        }),
      ),
    );
    expect(result.map((r) => r.status).sort()).toEqual([
      "fulfilled",
      "rejected",
    ]);
    const usage = Number(
      (
        await testPool.query(
          "SELECT sum(size_bytes) FROM publication_uploads WHERE user_id=2",
        )
      ).rows[0].sum,
    );
    expect(usage).toBe(uploadPolicy.regular.dailyBytes);
  });
  it("enforces hourly limits atomically, including simultaneous requests", async () => {
    const results = await Promise.allSettled(
      Array.from({ length: 8 }, () => takeRateLimit("fixture:rate", 3, 3600)),
    );
    expect(results.filter((r) => r.status === "fulfilled").length).toBe(3);
    expect(
      results
        .filter((r) => r.status === "rejected")
        .every((r) => r.reason.status === 429),
    ).toBeTrue();
  });
  it("keeps draft files private and checks status and exact file version for listening", async () => {
    const p = await prepared();
    expect(storage.puts[0].visibility).toBe("private");
    expect(storage.puts[0].ifAbsent).toBeTrue();
    const saved = (await testPool.query("SELECT files FROM catalog_uploads"))
      .rows[0].files[0];
    expect(saved.url).toBe("");
    expect(saved.presignedUrl).toBeUndefined();
    expect(saved.sourceUrl).toBeUndefined();
    const r = await admin({
      action: "save-track",
      uploadId: p.uploadId,
      ...meta,
    });
    expect(r.status).toBe(200);
    const id = (await r.json()).trackId;
    const url = (await testPool.query("SELECT audio_url FROM catalog_tracks"))
      .rows[0].audio_url;
    expect((await getMedia(url)).status).toBe(404);
    expect((await getMedia(url, 2)).status).toBe(404);
    expect((await getMedia(url, 1)).status).toBe(302);
    expect(
      (
        await admin({
          action: "set-status",
          trackId: id,
          revision: 1,
          status: "published",
        })
      ).status,
    ).toBe(200);
    const playable = await getMedia(url);
    expect(playable.status).toBe(302);
    expect(playable.headers.get("cache-control")).toContain("no-store");
    const wrong = new URL(url);
    wrong.searchParams.set("v", "0".repeat(32));
    expect((await getMedia(wrong.href)).status).toBe(404);
    expect(
      (
        await admin({
          action: "set-status",
          trackId: id,
          revision: 2,
          status: "archived",
        })
      ).status,
    ).toBe(200);
    expect((await getMedia(url)).status).toBe(404);
  });
  it("rejects HTML disguised as MP3 and oversized decoded image dimensions", async () => {
    const p = await prepared();
    storage.files.set(p.files[0].filename, {
      sizeBytes: 32,
      bytes: Buffer.from("<html><script>x</script></html> "),
    });
    expect(
      (await admin({ action: "save-track", uploadId: p.uploadId, ...meta }))
        .status,
    ).toBe(400);
    expect(
      (await testPool.query("SELECT * FROM catalog_tracks")).rows.length,
    ).toBe(0);
    const png = Buffer.alloc(33);
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]).copy(png);
    png.writeUInt32BE(13, 8);
    png.write("IHDR", 12);
    png.writeUInt32BE(20000, 16);
    png.writeUInt32BE(20000, 20);
    expect(() => checkMediaHeader(png, "image/png", png.length)).toThrow();
  });
  it("accepts MP3 audio after a large ID3 block without changing its complete fingerprint", async () => {
    const tagSize = 8 * 1024 * 1024;
    const bytes = Buffer.alloc(10 + tagSize + audio.length);
    bytes.write("ID3");
    bytes[3] = 4;
    for (let i = 0; i < 4; i++)
      bytes[6 + i] = (tagSize >>> ((3 - i) * 7)) & 127;
    audio.copy(bytes, 10 + tagSize);
    const prepared = await admin({
      action: "prepare-upload",
      files: [
        { part: "audio", contentType: "audio/mpeg", sizeBytes: bytes.length },
      ],
    });
    expect(prepared.status).toBe(200);
    const plan = await prepared.json();
    storage.files.set(plan.files[0].filename, {
      sizeBytes: bytes.length,
      bytes,
    });
    const response = await admin({
      action: "save-track",
      uploadId: plan.uploadId,
      ...meta,
    });
    expect(response.status).toBe(200);
    const id = (await response.json()).trackId;
    expect(
      (
        await testPool.query(
          "SELECT sha256 FROM catalog_audio_fingerprints WHERE track_id=$1",
          [id],
        )
      ).rows[0].sha256,
    ).toBe(sha(bytes));
  });
  it("bounds MP3 sampling across tiny chunks and rejects frames hidden only inside tags", () => {
    const tagSize = 8 * 1024 * 1024;
    const bytes = Buffer.alloc(10 + tagSize + 20000);
    bytes.write("ID3");
    bytes[3] = 4;
    bytes[5] = 16;
    for (let i = 0; i < 4; i++)
      bytes[6 + i] = (tagSize >>> ((3 - i) * 7)) & 127;
    const offset = 20 + tagSize;
    audio.copy(bytes, 100); // An embedded image/tag is never treated as audio.
    function sample(input) {
      const probe = new MediaHeaderProbe(
        "audio/mpeg",
        input.length,
        6 * 1024 * 1024,
      );
      for (let i = 0; i < 10; i++) probe.add(input.subarray(i, i + 1));
      probe.add(input.subarray(10, offset - 1));
      for (let i = offset - 1; i < offset + 20; i++)
        probe.add(input.subarray(i, i + 1));
      probe.add(input.subarray(offset + 20));
      return probe.bytes();
    }
    expect(sample(bytes).length).toBe(8195);
    expect(() =>
      checkMediaHeader(sample(bytes), "audio/mpeg", bytes.length),
    ).toThrow();
    audio.copy(bytes, offset);
    expect(() =>
      checkMediaHeader(sample(bytes), "audio/mpeg", bytes.length),
    ).not.toThrow();
    bytes[6] = 128;
    expect(() => sample(bytes)).toThrow();
    const truncated = Buffer.from(bytes);
    truncated[6] = 127;
    expect(() => sample(truncated)).toThrow();
    const plain = new MediaHeaderProbe(
      "audio/mpeg",
      audio.length,
      6 * 1024 * 1024,
    );
    for (const b of audio) plain.add(Uint8Array.of(b));
    expect(plain.bytes()).toEqual(audio);
    expect(() =>
      checkMediaHeader(plain.bytes(), "audio/mpeg", audio.length),
    ).not.toThrow();
  });
  it("preserves signed headers, blocks other accounts and reuses identical completed uploads", async () => {
    const id = randomUUID(),
      first = await publicationPart(id, "audio");
    expect(first.result.headers["If-None-Match"]).toBe("*");
    expect(first.result.headers["Content-Length"]).toBe("32");
    const retry = await publication.handle(
      post("publicationUpload", 2, { json: first.input }),
    );
    expect(retry.status).toBe(200);
    const retried = superjson.parse(await retry.text());
    expect(retried.storageKey).toBe(first.result.storageKey);
    expect(retried.alreadyUploaded).toBeTrue();
    const denied = await publication.handle(
      post("publicationUpload", 3, { json: first.input }),
    );
    expect(denied.status).toBe(403);
    const document = Buffer.from(
      JSON.stringify({
        title: "Title",
        artist: "Muwa",
        language: "ar",
        audioStorageKey: first.result.storageKey,
        coverStorageKey: null,
      }),
    );
    const marker = await publicationPart(id, "submission", document);
    const changed = await publication.handle(
      post("publicationUpload", 2, {
        json: { ...marker.input, sha256: "a".repeat(64) },
      }),
    );
    expect(changed.status).toBe(409);
    const differentAudio = await publication.handle(
      post("publicationUpload", 2, {
        json: { ...first.input, sha256: "a".repeat(64) },
      }),
    );
    expect(differentAudio.status).toBe(409);
  });
  it("allows retrying without an optional cover whose earlier upload was abandoned", async () => {
    const id = randomUUID(),
      first = await publicationPart(id, "audio");
    await reservePublication(2, false, {
      draftId: id,
      part: "cover",
      contentType: "image/jpeg",
      sizeBytes: 32,
    });
    await publicationPart(
      id,
      "submission",
      Buffer.from(
        JSON.stringify({
          title: "Title",
          artist: "Muwa",
          language: "ar",
          audioStorageKey: first.result.storageKey,
          coverStorageKey: null,
        }),
      ),
    );
    const result = await admin({ action: "refresh-submissions" });
    expect(result.status).toBe(200);
    expect((await result.json()).refreshed).toBe(1);
    const row = (
      await testPool.query(
        "SELECT status,cover_key FROM publication_drafts WHERE id=$1",
        [id],
      )
    ).rows[0];
    expect(row.status).toBe("pending");
    expect(row.cover_key).toBeNull();
  });
  it("snapshots reviewed files and rejects changed media and a copied approval with a different hash", async () => {
    const id = randomUUID(),
      first = await publicationPart(id, "audio");
    await publicationPart(
      id,
      "submission",
      Buffer.from(
        JSON.stringify({
          title: "Title",
          artist: "Muwa",
          language: "ar",
          audioStorageKey: first.result.storageKey,
          coverStorageKey: null,
        }),
      ),
    );
    const refresh = await admin({ action: "refresh-submissions" });
    expect(refresh.status).toBe(200);
    expect((await refresh.json()).refreshed).toBe(1);
    const row = (await testPool.query("SELECT * FROM publication_drafts"))
      .rows[0];
    expect(row.status).toBe("pending");
    expect(typeof row.media_snapshot).toBe("object");
    const changed = Buffer.from(audio);
    changed[31] = 1;
    storage.files.set(first.result.storageKey, {
      sizeBytes: 32,
      bytes: changed,
    });
    expect(
      (await admin({ action: "open-submission", submissionId: id })).status,
    ).toBe(409);
    storage.files.set(first.result.storageKey, { sizeBytes: 32, bytes: audio });
    const planResponse = await admin({
      action: "prepare-approval",
      submissionId: id,
      revision: row.revision,
    });
    expect(planResponse.status).toBe(200);
    const plan = await planResponse.json();
    storage.files.set(plan.files[0].filename, {
      sizeBytes: 32,
      bytes: changed,
    });
    expect(
      (
        await admin({
          action: "approve-submission",
          submissionId: id,
          revision: row.revision,
          uploadId: plan.uploadId,
          title: "Approved",
          artist: "Muwa",
          language: "ar",
          duration: 10,
        })
      ).status,
    ).toBe(409);
    expect(
      (await testPool.query("SELECT * FROM catalog_tracks")).rows.length,
    ).toBe(0);
  });
  it("never imports ownerless ready markers", async () => {
    const id = randomUUID(),
      audioKey = `publications/${id}/audio.mp3`;
    const body = Buffer.from(
      JSON.stringify({
        title: "Injected",
        artist: "X",
        audioStorageKey: audioKey,
      }),
    );
    storage.files.set(`publications/${id}/submission.json`, {
      sizeBytes: body.length,
      bytes: body,
    });
    storage.files.set(audioKey, { sizeBytes: 32, bytes: audio });
    expect(
      (await (await admin({ action: "refresh-submissions" })).json()).refreshed,
    ).toBe(0);
    expect(
      (await testPool.query("SELECT * FROM publication_drafts")).rows.length,
    ).toBe(0);
  });
  it("cleans abandoned plans, leaving fresh uploads and pending submissions intact", async () => {
    const old = await prepared(),
      fresh = await prepared();
    await testPool.query(
      "UPDATE catalog_uploads SET expires_at=now()-interval '25 hours' WHERE id=$1",
      [old.uploadId],
    );
    const draftId = randomUUID(),
      lease = await reservePublication(2, false, {
        draftId: draftId,
        part: "audio",
        contentType: "audio/mpeg",
        sizeBytes: 32,
      });
    storage.files.set(lease.filename, { sizeBytes: 32, bytes: audio });
    await testPool.query(
      "UPDATE publication_drafts SET status='pending',updated_at=now()-interval '3 days' WHERE id=$1",
      [draftId],
    );
    const clean = await admin({ action: "cleanup-uploads" });
    expect(clean.status).toBe(200);
    expect((await clean.json()).removed).toBe(1);
    expect(storage.files.has(old.files[0].filename)).toBeFalse();
    expect(storage.files.has(fresh.files[0].filename)).toBeTrue();
    expect(storage.files.has(lease.filename)).toBeTrue();
    expect(
      (
        await testPool.query(
          "SELECT deleted_at FROM catalog_uploads WHERE id=$1",
          [old.uploadId],
        )
      ).rows[0].deleted_at,
    ).not.toBeNull();
  });
  it("frees obsolete retry versions without deleting the reviewed version", async () => {
    const id = randomUUID(),
      old = await reservePublication(2, false, {
        draftId: id,
        part: "audio",
        contentType: "audio/mpeg",
        sizeBytes: 32,
      });
    storage.files.set(old.filename, { sizeBytes: 32, bytes: audio });
    const current = await reservePublication(2, false, {
      draftId: id,
      part: "audio",
      contentType: "audio/mpeg",
      sizeBytes: 32,
    });
    storage.files.set(current.filename, { sizeBytes: 32, bytes: audio });
    await testPool.query(
      "UPDATE publication_uploads SET expires_at=now()-interval '25 hours' WHERE draft_id=$1",
      [id],
    );
    await testPool.query(
      "UPDATE publication_drafts SET status='pending' WHERE id=$1",
      [id],
    );
    const result = await admin({ action: "cleanup-uploads" });
    expect(result.status).toBe(200);
    expect(storage.files.has(old.filename)).toBeFalse();
    expect(storage.files.has(current.filename)).toBeTrue();
  });
  it("accepts only safe diagnostics fields, deduplicates IDs and restricts the server journal to admins", async () => {
    const payload = {
      platform: "Android",
      version: "1.4.0",
      build: "39",
      events: [
        {
          id: randomUUID(),
          occurredAt: new Date().toISOString(),
          area: "playback",
          errorType: "playback",
          errorCode: 1001,
        },
      ],
    };
    expect(
      (await diagnostics.handle(post("diagnostics/events", 0, payload))).status,
    ).toBe(401);
    expect(
      (
        await diagnostics.handle(
          post("diagnostics/events", 2, {
            ...payload,
            password: "must-not-store",
          }),
        )
      ).status,
    ).toBe(400);
    expect(
      (await diagnostics.handle(post("diagnostics/events", 2, payload))).status,
    ).toBe(200);
    expect(
      (await diagnostics.handle(post("diagnostics/events", 2, payload))).status,
    ).toBe(200);
    const rows = (await testPool.query("SELECT * FROM muwa_diagnostics")).rows;
    expect(rows.length).toBe(1);
    expect(rows[0].user_id).toBe(2);
    const journal = (user) =>
      adminService.handle(
        new Request(
          "https://muwa-app.floot.app/_api/admin/state?section=errors",
          { headers: { "x-fixture-user": String(user) } },
        ),
        "GET",
      );
    expect((await journal(2)).status).toBe(403);
    const r = await journal(1);
    expect(r.status).toBe(200);
    const body = await r.json();
    expect(body.errors.length).toBe(1);
    expect(body.errors[0].userId).toBeUndefined();
    expect(body.errors[0].stack).toBeUndefined();
  });
});
