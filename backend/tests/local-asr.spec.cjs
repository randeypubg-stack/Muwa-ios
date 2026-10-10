const fs = require("node:fs"),
  path = require("node:path");
const { randomUUID } = require("node:crypto");
const { testPool } = require("./db");
const { adminService } = require("./adminService");
const storage = require("./testStorage");
const root = path.resolve(__dirname, "../..");
const file = "catalog/12345678-1234-1234-1234-123456789abc/audio.mp3";
const sha = "a".repeat(64);
async function query(sql, args = []) {
  return (await testPool.query(sql, args)).rows;
}
async function request(action, user = 1) {
  return adminService.handle(
    new Request("https://muwa-app.floot.app/_api/admin/action", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-fixture-user": String(user),
      },
      body: JSON.stringify(action),
    }),
    "POST",
  );
}
async function create(id = "asr-fixture") {
  await query(
    "INSERT INTO catalog_tracks(id,title,artist,language,duration,audio_url,audio_filename,status) VALUES($1,'Nasheed','Muwa','ar',10,'https://storage.invalid/audio.mp3',$2,'draft')",
    [id, file],
  );
  await query(
    "INSERT INTO catalog_audio_fingerprints(track_id,sha256) VALUES($1,$2)",
    [id, sha],
  );
  return (await query("SELECT muwa_enqueue_asr($1) AS id", [id]))[0].id;
}
async function claim(token = randomUUID()) {
  const rows = await query("SELECT * FROM muwa_claim_asr($1)", [token]);
  return rows.length ? { job: rows[0], token } : null;
}
async function state() {
  const response = await adminService.handle(
    new Request("https://muwa-app.floot.app/_api/admin/state?section=catalog", {
      headers: { "x-fixture-user": "1" },
    }),
    "GET",
  );
  expect(response.status).toBe(200);
  return response.json();
}
const doc = (id) => ({
  version: 2,
  id,
  language: "ar",
  segments: [
    {
      id: "s0",
      start: 1,
      end: 3,
      original: "مرحبا",
      words: [{ text: "مرحبا", start: 1, end: 3 }],
      timing: "estimated",
    },
  ],
});
const quality = {
  needsReview: false,
  model: "Whisper large-v3 / CPU int8",
  languageProbability: 1,
  warnings: [],
  elapsedSeconds: 3,
};
async function finish(c, value = doc(c.job.id), q = quality) {
  return (
    await query("SELECT muwa_finish_asr($1,$2,$3::jsonb,$4::jsonb) AS ok", [
      c.job.id,
      c.token,
      JSON.stringify(value),
      JSON.stringify(q),
    ])
  )[0].ok;
}
describe("Local recognition queue and protected captions", () => {
  let restore, enabled;
  beforeAll(async () => {
    restore = storage.installFetch();
    for (const name of [
      "admin-migration.sql",
      "security-migration.sql",
      "telegram-import-migration.sql",
      "asr-migration.sql",
      "asr-migration.sql",
    ])
      await query(fs.readFileSync(path.join(root, name), "utf8"));
  });
  afterAll(() => restore());
  beforeEach(async () => {
    enabled = process.env.MUWA_LOCAL_ASR_ENABLED;
    process.env.MUWA_LOCAL_ASR_ENABLED = "1";
    await query(
      "TRUNCATE catalog_tracks,catalog_uploads,publication_drafts,admin_audit_events,muwa_request_limits CASCADE",
    );
    storage.files.clear();
  });
  afterEach(() => {
    if (enabled === undefined) delete process.env.MUWA_LOCAL_ASR_ENABLED;
    else process.env.MUWA_LOCAL_ASR_ENABLED = enabled;
  });
  it("maps Arabic regional and dialect tags to original Arabic transcription", async () => {
    for (const language of [
      "ar",
      "ar-Arab-EG",
      "ar-EG",
      "ar-SA",
      "ar-IQ",
      "ar-MA",
      "ar-DZ",
      "ar-SY",
      "ar-AE",
      "ar-TN",
      "ar-YE",
      "arz",
      "ary",
      "acm",
      "apc",
      "arb",
      "apd",
      "ars",
      "acq",
      "shu",
      "abv",
      "aao",
      "ayp",
    ]) {
      expect(
        (await query("select muwa_asr_language($1) as language", [language]))[0]
          .language,
      ).toBe("ar");
    }
    expect(
      (await query("select muwa_asr_language('und') as language"))[0].language,
    ).toBe("und");
    expect(
      (await query("select muwa_asr_language('ru') as language"))[0].language,
    ).toBe("ru");
    const id = await create();
    await query("update catalog_tracks set language='ar-EG'");
    expect(
      (await query("select muwa_enqueue_asr('asr-fixture') as id"))[0].id,
    ).toBe(id);
    const c = await claim();
    expect(c.job.language).toBe("ar");
    expect(await finish(c)).toBeTrue();
    expect(
      (await query("select captions from catalog_tracks"))[0].captions[0].ar,
    ).toBe("مرحبا");
  });
  it("automatically queues a verified upload and deduplicates subsequent metadata saves", async () => {
    const p = await (
      await request({
        action: "prepare-upload",
        files: [{ part: "audio", contentType: "audio/mpeg", sizeBytes: 32 }],
      })
    ).json();
    storage.files.set(p.files[0].filename, { sizeBytes: 32 });
    const meta = {
      title: "Nasheed",
      artist: "Muwa",
      language: "ar",
      duration: 10,
      status: "draft",
    };
    const saved = await request({
      action: "save-track",
      uploadId: p.uploadId,
      ...meta,
    });
    expect(saved.status).toBe(200);
    const id = (await saved.json()).trackId;
    expect(
      (
        await query("SELECT status FROM catalog_asr_jobs WHERE track_id=$1", [
          id,
        ])
      )[0].status,
    ).toBe("queued");
    expect(
      (
        await request({
          action: "save-track",
          trackId: id,
          revision: 1,
          ...meta,
        })
      ).status,
    ).toBe(200);
    expect(
      (await query("SELECT count(*)::int AS n FROM catalog_asr_jobs"))[0].n,
    ).toBe(1);
  });
  it("runs at most one inference and rejects foreign or expired lease completions", async () => {
    await create("first");
    await create("second");
    const claims = await Promise.all([claim(), claim()]);
    expect(claims.filter(Boolean).length).toBe(1);
    const c = claims.find(Boolean);
    expect(
      (
        await query("SELECT muwa_heartbeat_asr($1,$2,1) AS ok", [
          c.job.id,
          randomUUID(),
        ])
      )[0].ok,
    ).toBeFalse();
    expect(await finish({ ...c, token: randomUUID() })).toBeFalse();
    await query(
      "UPDATE catalog_asr_jobs SET lease_until=now()-interval '1 second' WHERE id=$1",
      [c.job.id],
    );
    expect(await finish(c)).toBeFalse();
    const replacement = await claim();
    expect(replacement.job.id).toBe(c.job.id);
    expect(replacement.job.attempts).toBe(2);
  });
  it("saves original text and acoustic words automatically without publishing the track", async () => {
    await create();
    const c = await claim();
    expect(await finish(c)).toBeTrue();
    const t = (await query("SELECT * FROM catalog_tracks"))[0];
    expect(t.status).toBe("draft");
    expect(t.captions_source).toBe("automatic");
    expect(t.captions[0].ar).toBe("مرحبا");
    expect(t.captions[0].ru).toBe("");
    expect(t.captions[0].words.length).toBe(1);
    expect(t.captions_revision).toBe(1);
    expect(await finish(c)).toBeFalse();
  });
  it("counts current recognition, exposes title suggestions privately and never renames a track", async () => {
    await create();
    const c = await claim();
    const original = "يا رب إن القلب يرجو رحمتك";
    const value = doc(c.job.id);
    value.segments[0].original = original;
    value.segments[0].words = [];
    value.segments[0].timing = "phrase";
    expect(
      await finish(c, value, { ...quality, needsReview: true }),
    ).toBeTrue();
    const result = await (
      await request({ action: "get-recognition", trackId: "asr-fixture" })
    ).json();
    expect(result.titleSuggestion.title).toBe(original);
    expect(result.titleSuggestion.needsReview).toBeTrue();
    expect(result.trackRevision).toBe(1);
    expect(
      (await query("select title,captions from catalog_tracks"))[0],
    ).toEqual({ title: "Nasheed", captions: [] });
    const overview = await state();
    expect(overview.recognition.counts).toEqual({
      queued: 0,
      processing: 0,
      ready: 0,
      review: 1,
      failed: 0,
      missing: 0,
    });
    expect(
      (await request({ action: "get-recognition", trackId: "asr-fixture" }, 2))
        .status,
    ).toBe(403);
    await query("update catalog_audio_fingerprints set sha256=$1", [
      "b".repeat(64),
    ]);
    const replaced = await state();
    expect(replaced.recognition.counts.review).toBe(0);
    expect(replaced.recognition.counts.missing).toBe(1);
    expect(
      (
        await (
          await request({ action: "get-recognition", trackId: "asr-fixture" })
        ).json()
      ).titleSuggestion,
    ).toBeNull();
  });
  it("preserves a manual edit performed while the model is running", async () => {
    await create();
    const c = await claim();
    const r = await request({
      action: "save-captions",
      trackId: "asr-fixture",
      revision: 1,
      captions: [{ start: 1, end: 2, ar: "تصحيح يدوي", ru: "", en: "" }],
    });
    expect(r.status).toBe(200);
    expect(await finish(c)).toBeTrue();
    const t = (await query("SELECT * FROM catalog_tracks"))[0];
    expect(t.captions[0].ar).toBe("تصحيح يدوي");
    expect(t.captions_source).toBe("manual");
    expect((await query("SELECT status FROM catalog_asr_jobs"))[0].status).toBe(
      "ready",
    );
  });
  it("preserves intentionally cleared manual captions even when recognition starts later", async () => {
    await create();
    await query(
      "UPDATE catalog_tracks SET captions_revision=2,captions='[]'::jsonb,captions_source='manual'",
    );
    await query("DELETE FROM catalog_asr_jobs");
    await query("SELECT muwa_enqueue_asr('asr-fixture')");
    const c = await claim();
    expect(await finish(c)).toBeTrue();
    const t = (await query("SELECT * FROM catalog_tracks"))[0];
    expect(t.captions).toEqual([]);
    expect(t.captions_revision).toBe(2);
    expect(t.captions_source).toBe("manual");
  });
  it("invalidates a replaced recording and refuses to attach the previous result", async () => {
    await create();
    const c = await claim();
    await query(
      "UPDATE catalog_tracks SET audio_filename='catalog/abcdefab-1234-1234-1234-123456789abc/audio.mp3' WHERE id='asr-fixture'",
    );
    await query("UPDATE catalog_audio_fingerprints SET sha256=$1", [
      "b".repeat(64),
    ]);
    await query("SELECT muwa_enqueue_asr('asr-fixture')");
    expect(await finish(c)).toBeFalse();
    expect(
      (await query("SELECT captions FROM catalog_tracks"))[0].captions,
    ).toEqual([]);
    expect(
      (
        await query(
          "SELECT count(*)::int AS n FROM catalog_asr_jobs WHERE status='queued'",
        )
      )[0].n,
    ).toBe(1);
  });
  it("holds uncertain text for review, exposes it only to admins and reserves reruns for the owner", async () => {
    await create();
    const c = await claim();
    expect(
      await finish(c, doc(c.job.id), {
        ...quality,
        needsReview: true,
        warnings: ["UNCERTAIN_PHRASE"],
      }),
    ).toBeTrue();
    expect(
      (await query("SELECT captions FROM catalog_tracks"))[0].captions,
    ).toEqual([]);
    expect(
      (await request({ action: "get-recognition", trackId: "asr-fixture" }, 2))
        .status,
    ).toBe(403);
    const r = await request({
      action: "get-recognition",
      trackId: "asr-fixture",
    });
    expect(r.status).toBe(200);
    expect((await r.json()).recognition.document.language).toBe("ar");
    expect(
      (
        await request(
          { action: "recognize-track", trackId: "asr-fixture", revision: 1 },
          4,
        )
      ).status,
    ).toBe(403);
    expect(
      (
        await request({
          action: "recognize-track",
          trackId: "asr-fixture",
          revision: 1,
        })
      ).status,
    ).toBe(200);
  });
  it("rejects malformed versions, IDs, timing overlaps and null review flags at the database boundary", async () => {
    await create();
    const c = await claim();
    for (const bad of [
      { ...doc(c.job.id), version: null },
      { ...doc(c.job.id), id: null },
      {
        ...doc(c.job.id),
        segments: [
          ...doc(c.job.id).segments,
          {
            id: "s1",
            start: 2,
            end: 4,
            original: "overlap",
            words: [],
            timing: "phrase",
          },
        ],
      },
    ])
      await expectAsync(finish(c, bad)).toBeRejected();
    await expectAsync(
      finish(c, doc(c.job.id), { ...quality, needsReview: null }),
    ).toBeRejected();
    expect(
      (await query("SELECT captions FROM catalog_tracks"))[0].captions,
    ).toEqual([]);
  });
  it("limits crash recovery to three attempts and does not grant worker functions to PUBLIC", async () => {
    await create();
    const c = await claim();
    await query(
      "UPDATE catalog_asr_jobs SET attempts=3,lease_until=now()-interval '1 second'",
    );
    expect(await claim()).toBeNull();
    expect(
      (await query("SELECT status,error_code FROM catalog_asr_jobs"))[0],
    ).toEqual({ status: "failed", error_code: "LEASE_EXPIRED" });
    const exposed = await query(
      "SELECT count(*)::int AS n FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a WHERE p.proname LIKE 'muwa_%asr' AND a.grantee=0 AND a.privilege_type='EXECUTE'",
    );
    expect(exposed[0].n).toBe(0);
  });
});
