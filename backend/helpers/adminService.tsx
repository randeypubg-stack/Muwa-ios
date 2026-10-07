import { randomUUID } from "node:crypto";
import { sql, type Transaction } from "kysely";
import { upload, getInfo, getUrl, listFolder } from "./storage";
import { db } from "./db";
import type { DB, Json } from "./schema";
import { getServerUserSession } from "./getServerUserSession";
import { NotAuthenticatedError, setServerSession } from "./getSetServerSession";
import {
  adminValidation,
  type AdminAction,
  type AdminQuery,
  type AdminState,
  type AdminResult,
  type UploadFile,
  type Caption,
} from "./adminValidation";
import {
  guardMutation,
  readJSONLimited,
  secureJSON,
  SecurityError,
} from "./requestSecurity";
import {
  reserveCatalog,
  takeRateLimit,
  validPublicationKey,
} from "./uploadSecurity";
import { cleanupExpiredUploads } from "./uploadCleanup";
import { telegramImportOwnerAllowed } from "./runtimeConfig";
import {
  findTelegramSource,
  findAudioDuplicate,
  telegramSourceDetails,
  lockAudio,
  lockTelegramSource,
  rememberAudio,
  rememberTelegramSource,
} from "./telegramImport";
import {
  inspectStoredMedia,
  catalogueMediaURL,
  type MediaFingerprint,
} from "./mediaSecurity";
function fail(message: string, status = 400): never {
  throw new SecurityError(message, status);
}
const json = secureJSON;
async function audit(
  tx: Transaction<DB>,
  actorId: number,
  action: string,
  entityId: string,
  details: Json = {},
) {
  await tx
    .insertInto("adminAuditEvents")
    .values({ actorId, action, entityId, details })
    .execute();
}
async function track(
  tx: Transaction<DB>,
  id: string,
  revision: number | undefined,
) {
  const row = await tx
    .selectFrom("catalogTracks")
    .selectAll()
    .where("id", "=", id)
    .forUpdate()
    .executeTakeFirst();
  if (!row) fail("Нашид не найден.", 404);
  if (row.revision !== revision)
    fail(
      "Запись изменена в другой сессии. Обновите список и откройте её заново.",
      409,
    );
  return row;
}
async function submission(tx: Transaction<DB>, id: string, revision: number) {
  const row = await tx
    .selectFrom("publicationDrafts")
    .selectAll()
    .where("id", "=", id)
    .forUpdate()
    .executeTakeFirst();
  if (!row) fail("Публикация не найдена.", 404);
  if (row.status !== "pending" || row.revision !== revision)
    fail("Публикация уже обработана или изменена. Обновите список.", 409);
  return row;
}
const ext: Record<string, string> = {
  "audio/mpeg": "mp3",
  "audio/mp4": "m4a",
  "audio/x-m4a": "m4a",
  "audio/wav": "wav",
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};
async function prepare(
  userId: number,
  files: {
    part: "audio" | "cover";
    contentType: string;
    sizeBytes: number;
    sourceUrl?: string;
    sourceSha256?: string;
  }[],
  trackId?: string,
  submissionId?: string,
): Promise<AdminResult> {
  if (new Set(files.map((f) => f.part)).size !== files.length)
    fail("Один файл на каждое назначение.");
  const id = randomUUID();
  const saved = files.map(({ part, contentType, sizeBytes, sourceSha256 }) => ({
    part,
    contentType,
    sizeBytes,
    filename: `catalog/${id}/${part}.${ext[contentType]}`,
    url: "",
    visibility: "private" as const,
    ...(sourceSha256 ? { sourceSha256 } : {}),
  }));
  // Reserve aggregate capacity under the account lock before issuing any PUT.
  await reserveCatalog(
    userId,
    id,
    saved,
    files.reduce((sum, f) => sum + f.sizeBytes, 0),
    trackId,
    submissionId,
  );
  const prepared: UploadFile[] = [];
  for (let i = 0; i < saved.length; i++) {
    const file = saved[i];
    const result = await upload({
      visibility: "private",
      filename: file.filename,
      contentType: file.contentType,
      sizeBytes: file.sizeBytes,
      ifAbsent: true,
      expiresInSeconds: 900,
    });
    if (!result.ok)
      fail("Не удалось подготовить хранилище. Повторите позже.", 503);
    prepared.push({
      ...file,
      sourceUrl: files[i].sourceUrl,
      presignedUrl: result.presignedUrl,
      headers: result.headers,
    });
  }
  return { ok: true, uploadId: id, files: prepared };
}
async function verifiedPlan(
  id: string,
  userId: number,
  trackId?: string,
  submissionId?: string,
) {
  const row = await db
    .selectFrom("catalogUploads")
    .selectAll()
    .where("id", "=", id)
    .where("userId", "=", userId)
    .executeTakeFirst();
  if (
    !row ||
    row.consumedAt ||
    row.expiresAt <= new Date() ||
    row.trackId !== (trackId ?? null) ||
    row.submissionId !== (submissionId ?? null)
  )
    fail("Загрузка устарела. Подготовьте файлы заново.", 409);
  const files = row.files as unknown as UploadFile[];
  const verified: (UploadFile & { fingerprint: MediaFingerprint })[] = [];
  for (const file of files) {
    const checked = await inspectStoredMedia(
      file.visibility ?? "public",
      file.filename,
      file.part,
      file.sizeBytes,
      file.contentType,
    );
    if (file.sourceSha256 && checked.fingerprint.sha256 !== file.sourceSha256)
      fail("Скопированный файл отличается от проверенной публикации.", 409);
    verified.push({ ...file, fingerprint: checked.fingerprint });
  }
  return verified;
}
async function consume(tx: Transaction<DB>, id: string, userId: number) {
  const result = await tx
    .updateTable("catalogUploads")
    .set({ consumedAt: new Date() })
    .where("id", "=", id)
    .where("userId", "=", userId)
    .where("consumedAt", "is", null)
    .where("expiresAt", ">", new Date())
    .returning("id")
    .executeTakeFirst();
  if (!result) fail("Эта загрузка уже использована или устарела.", 409);
}
async function privateFile(
  key: string | null,
  id: string,
  part: "audio" | "cover",
  snapshot?: MediaFingerprint,
) {
  if (!key) return null;
  if (!validPublicationKey(key, id, part))
    fail("Некорректный путь публикации.");
  const extension = key.split(".").pop();
  const mime = Object.entries(ext).find(([, v]) => v === extension)?.[0];
  if (!mime || !mime.startsWith(part === "audio" ? "audio/" : "image/"))
    fail("Формат публикации не поддерживается.");
  const checked = await inspectStoredMedia(
    "private",
    key,
    part,
    snapshot?.sizeBytes,
    mime,
  );
  if (
    snapshot &&
    (snapshot.etag !== checked.fingerprint.etag ||
      snapshot.sha256 !== checked.fingerprint.sha256)
  )
    fail("Файл изменён после отправки на проверку.", 409);
  const source = await getUrl({
    visibility: "private",
    filename: key,
    expiresInSeconds: 300,
  });
  if (!source.ok) fail("Файл публикации недоступен.");
  return {
    part,
    contentType: mime,
    sizeBytes: checked.fingerprint.sizeBytes,
    sourceUrl: source.url,
    sourceSha256: checked.fingerprint.sha256,
    fingerprint: checked.fingerprint,
  };
}
async function refresh(
  userId: number,
  cursor?: { token?: string; offset: number },
) {
  const listing = await listFolder({
    visibility: "private",
    key: "publications/",
    continuationToken: cursor?.token,
  });
  if (!listing.ok) fail("Не удалось прочитать публикации.", 503);
  let refreshed = 0;
  const offset = cursor?.offset ?? 0;
  for (const folder of listing.folders.slice(offset, offset + 25)) {
    const id = folder
      .replace(/^private\//, "")
      .replace(/\/$/, "")
      .split("/")
      .pop()!;
    if (!/^[0-9a-f-]{36}$/i.test(id)) continue;
    const existing = await db
      .selectFrom("publicationDrafts")
      .selectAll()
      .where("id", "=", id)
      .executeTakeFirst();
    // A ready marker alone must never create an ownerless/moderatable submission.
    if (!existing || !existing.userId || existing.status !== "uploading")
      continue;
    const filename = `publications/${id}/submission.json`;
    const info = await getInfo({ visibility: "private", filename });
    if (!info.ok || !info.exists) continue;
    try {
      const checked = await inspectStoredMedia(
        "private",
        filename,
        "submission",
        undefined,
        "application/json",
      );
      const data = checked.json;
      if (!data || typeof data !== "object") continue;
      const value = data as Record<string, unknown>;
      if (
        typeof value.title !== "string" ||
        !value.title.trim() ||
        value.title.length > 180 ||
        typeof value.artist !== "string" ||
        !value.artist.trim() ||
        value.artist.length > 180 ||
        typeof value.audioStorageKey !== "string"
      )
        continue;
      const audioKey = value.audioStorageKey,
        coverKey =
          typeof value.coverStorageKey === "string"
            ? value.coverStorageKey
            : null;
      if (
        audioKey !== existing.audioKey ||
        (coverKey !== null && coverKey !== existing.coverKey)
      )
        continue;
      const leases = await sql<{
        filename: string;
        expectedSha256: string | null;
        sizeBytes: string;
      }>`select filename,expected_sha256,size_bytes from publication_uploads where draft_id=${id} and user_id=${existing.userId} and deleted_at is null`.execute(
        db,
      );
      const audio = await privateFile(audioKey, id, "audio"),
        cover = await privateFile(coverKey, id, "cover");
      if (!audio) continue;
      const fingerprints: Record<string, MediaFingerprint> = {
        [filename]: checked.fingerprint,
        [audioKey]: audio.fingerprint,
        ...(cover && coverKey ? { [coverKey]: cover.fingerprint } : {}),
      };
      if (
        leases.rows.some(
          (lease) =>
            fingerprints[lease.filename] &&
            (Number(lease.sizeBytes) !==
              fingerprints[lease.filename].sizeBytes ||
              (lease.expectedSha256 &&
                lease.expectedSha256 !== fingerprints[lease.filename].sha256)),
        )
      )
        continue;
      // Newly versioned keys require a reservation owned by this account.
      if (
        Object.keys(fingerprints).some(
          (key) =>
            /\/(audio|cover)-/.test(key) &&
            !leases.rows.some((l) => l.filename === key),
        )
      )
        continue;
      await db.transaction().execute(async (tx) => {
        await tx
          .selectFrom("users")
          .select("id")
          .where("id", "=", existing.userId!)
          .forUpdate()
          .executeTakeFirstOrThrow();
        const result = await tx
          .updateTable("publicationDrafts")
          .set({
            status: "pending",
            audioKey,
            coverKey,
            title: value.title as string,
            artist: value.artist as string,
            language:
              typeof value.language === "string"
                ? value.language.slice(0, 10)
                : "ar",
            updatedAt: new Date(),
            revision: sql`publication_drafts.revision+1`,
          })
          .where("id", "=", id)
          .where("status", "=", "uploading")
          .where("revision", "=", existing.revision)
          .returning("id")
          .executeTakeFirst();
        if (result) {
          await sql`update publication_drafts set media_snapshot=${fingerprints} where id=${id}`.execute(
            tx,
          );
          await audit(tx, userId, "submission.received", id);
          refreshed++;
        }
      });
    } catch (error) {
      if (!(error instanceof SecurityError))
        throw error; /* Invalid upload remains private; other submissions can still be reviewed. */
    }
  }
  const nextCursor =
    offset + 25 < listing.folders.length
      ? { token: cursor?.token, offset: offset + 25 }
      : listing.nextContinuationToken
        ? { token: listing.nextContinuationToken, offset: 0 }
        : undefined;
  return { ok: true as const, refreshed, nextCursor };
}
async function execute(
  input: AdminAction,
  userId: number,
): Promise<AdminResult> {
  if (input.action === "lookup-telegram-import") {
    const id = await findTelegramSource(input.source);
    return {
      ok: true,
      ...(id ? { trackId: id } : {}),
      importStatus: id ? "existing" : "missing",
    };
  }
  if (input.action === "cleanup-uploads") return cleanupExpiredUploads(userId);
  if (input.action === "refresh-submissions")
    return refresh(userId, input.cursor);
  if (input.action === "prepare-upload") {
    if (input.trackId)
      await db
        .transaction()
        .execute((tx) => track(tx, input.trackId!, input.revision));
    return prepare(userId, input.files, input.trackId);
  }
  if (
    input.action === "open-submission" ||
    input.action === "prepare-approval"
  ) {
    const row = await db
      .selectFrom("publicationDrafts")
      .selectAll()
      .where("id", "=", input.submissionId)
      .executeTakeFirst();
    if (!row) fail("Публикация не найдена.", 404);
    if (
      input.action === "prepare-approval" &&
      (row.status !== "pending" || row.revision !== input.revision)
    )
      fail("Публикация уже обработана или изменена.", 409);
    const snapshot = (
      await sql<{
        mediaSnapshot: Record<string, MediaFingerprint> | null;
      }>`select media_snapshot from publication_drafts where id=${row.id}`.execute(
        db,
      )
    ).rows[0]?.mediaSnapshot;
    const audio = await privateFile(
      row.audioKey,
      row.id,
      "audio",
      row.audioKey ? snapshot?.[row.audioKey] : undefined,
    );
    const cover = await privateFile(
      row.coverKey,
      row.id,
      "cover",
      row.coverKey ? snapshot?.[row.coverKey] : undefined,
    );
    if (!audio) fail("Аудио отсутствует.");
    if (input.action === "open-submission")
      return {
        ok: true,
        audioUrl: audio.sourceUrl,
        artworkUrl: cover?.sourceUrl,
      };
    return prepare(
      userId,
      [audio, ...(cover ? [cover] : [])],
      undefined,
      row.id,
    );
  }
  if (
    input.action === "save-track" ||
    input.action === "import-telegram-track"
  ) {
    const source =
      input.action === "import-telegram-track" ? input.source : null;
    const trackId = input.action === "save-track" ? input.trackId : undefined;
    const revision = input.action === "save-track" ? input.revision : undefined;
    // Recover a lost response even when the old upload lease was consumed or
    // expired. Only the same stored source and verified audio hash can match.
    if (source) {
      const existing = await findTelegramSource(source);
      if (existing)
        return { ok: true, trackId: existing, importStatus: "existing" };
    }
    const files = input.uploadId
      ? await verifiedPlan(input.uploadId, userId, trackId)
      : [];
    const audio = files.find((f) => f.part === "audio"),
      cover = files.find((f) => f.part === "cover");
    if (source && (!audio || audio.fingerprint.sha256 !== source.audioSha256))
      fail(
        "Контрольная сумма импортируемого аудио не совпадает с загруженным файлом.",
        409,
      );
    return db.transaction().execute<AdminResult>(async (tx) => {
      if (source) await lockTelegramSource(tx, source);
      if (audio) await lockAudio(tx, audio.fingerprint.sha256);
      if (source) {
        const existing = await findTelegramSource(source, tx);
        if (existing)
          return { ok: true, trackId: existing, importStatus: "existing" };
        const duplicate = await findAudioDuplicate(tx, source.audioSha256);
        if (duplicate) {
          await rememberTelegramSource(tx, source, duplicate, userId);
          // The unused private lease stays unconsumed for normal cleanup.
          await audit(
            tx,
            userId,
            "telegram.linked",
            duplicate,
            telegramSourceDetails(source),
          );
          return { ok: true, trackId: duplicate, importStatus: "duplicate" };
        }
      }
      const current = trackId ? await track(tx, trackId, revision) : null;
      if (!current && !audio) fail("Сначала загрузите аудио.");
      const id = current?.id ?? `muwa-${randomUUID()}`;
      const values = {
        title: input.title,
        artist: input.artist,
        language: input.language,
        duration: input.duration,
        status: input.status,
        audioUrl: audio
          ? audio.visibility === "private"
            ? catalogueMediaURL(id, "audio", audio.filename)
            : audio.url
          : (current?.audioUrl ?? null),
        audioFilename: audio?.filename ?? current?.audioFilename ?? null,
        artworkUrl: cover
          ? cover.visibility === "private"
            ? catalogueMediaURL(id, "cover", cover.filename)
            : cover.url
          : (current?.artworkUrl ?? null),
        coverFilename: cover?.filename ?? current?.coverFilename ?? null,
        updatedAt: new Date(),
      };
      if (input.status === "published" && !values.audioUrl)
        fail("Нельзя публиковать без аудио.");
      if (input.uploadId) await consume(tx, input.uploadId, userId);
      // Replacing audio invalidates old timings; never silently attach old captions to new audio.
      const captionsChanged = !!audio && !!current;
      if (current)
        await tx
          .updateTable("catalogTracks")
          .set({
            ...values,
            revision: current.revision + 1,
            ...(captionsChanged
              ? { captions: [], captionsRevision: current.captionsRevision + 1 }
              : {}),
          })
          .where("id", "=", id)
          .execute();
      else
        await tx
          .insertInto("catalogTracks")
          .values({ ...values, id, createdBy: userId })
          .execute();
      if (audio) await rememberAudio(tx, id, audio.fingerprint.sha256);
      if (source) await rememberTelegramSource(tx, source, id, userId);
      await audit(tx, userId, current ? "track.updated" : "track.created", id, {
        title: input.title,
        status: input.status,
        audioReplaced: !!audio,
      });
      if (source)
        await audit(
          tx,
          userId,
          "telegram.imported",
          id,
          telegramSourceDetails(source),
        );
      return {
        ok: true,
        trackId: id,
        ...(source ? { importStatus: "created" as const } : {}),
      };
    });
  }
  if (input.action === "set-status" || input.action === "save-captions")
    return db.transaction().execute(async (tx) => {
      const row = await track(tx, input.trackId, input.revision);
      if (input.action === "set-status") {
        if (
          input.status === "published" &&
          (!row.audioUrl || row.duration <= 0 || !row.title.trim())
        )
          fail("Заполните название и загрузите аудио.");
        await tx
          .updateTable("catalogTracks")
          .set({
            status: input.status,
            revision: row.revision + 1,
            updatedAt: new Date(),
          })
          .where("id", "=", row.id)
          .execute();
        await audit(tx, userId, "track." + input.status, row.id);
      } else {
        if (input.captions.some((c) => c.end > row.duration + 0.1))
          fail("Субтитры выходят за длительность аудио.");
        await tx
          .updateTable("catalogTracks")
          .set({
            captions: input.captions,
            captionsRevision: row.captionsRevision + 1,
            revision: row.revision + 1,
            updatedAt: new Date(),
          })
          .where("id", "=", row.id)
          .execute();
        await audit(tx, userId, "captions.updated", row.id, {
          lines: input.captions.length,
        });
      }
      return { ok: true };
    });
  if (input.action === "reject-submission")
    return db.transaction().execute(async (tx) => {
      const row = await submission(tx, input.submissionId, input.revision);
      await tx
        .updateTable("publicationDrafts")
        .set({
          status: "rejected",
          rejectionReason: input.reason,
          revision: row.revision + 1,
          updatedAt: new Date(),
        })
        .where("id", "=", row.id)
        .execute();
      await audit(tx, userId, "submission.rejected", row.id, {
        reason: input.reason,
      });
      return { ok: true };
    });
  if (input.action === "approve-submission") {
    const files = await verifiedPlan(
      input.uploadId,
      userId,
      undefined,
      input.submissionId,
    );
    const audio = files.find((f) => f.part === "audio"),
      cover = files.find((f) => f.part === "cover");
    if (!audio) fail("Аудио не загружено.");
    return db.transaction().execute(async (tx) => {
      await lockAudio(tx, audio.fingerprint.sha256);
      const row = await submission(tx, input.submissionId, input.revision);
      await consume(tx, input.uploadId, userId);
      const id = `muwa-${row.id}`;
      await tx
        .insertInto("catalogTracks")
        .values({
          id,
          title: input.title,
          artist: input.artist,
          language: input.language,
          duration: input.duration,
          status: "published",
          audioUrl:
            audio.visibility === "private"
              ? catalogueMediaURL(id, "audio", audio.filename)
              : audio.url,
          audioFilename: audio.filename,
          artworkUrl: cover
            ? cover.visibility === "private"
              ? catalogueMediaURL(id, "cover", cover.filename)
              : cover.url
            : null,
          coverFilename: cover?.filename ?? null,
          sourceSubmissionId: row.id,
          createdBy: userId,
        })
        .execute();
      await rememberAudio(tx, id, audio.fingerprint.sha256);
      await tx
        .updateTable("publicationDrafts")
        .set({
          status: "published",
          trackId: id,
          revision: row.revision + 1,
          updatedAt: new Date(),
        })
        .where("id", "=", row.id)
        .execute();
      await audit(tx, userId, "submission.published", row.id, { trackId: id });
      return { ok: true, trackId: id };
    });
  }
  fail("Неизвестное действие.");
}
async function state(input: AdminQuery): Promise<AdminState> {
  const count = await db
    .selectFrom("catalogTracks")
    .select(["status", sql<number>`count(*)::integer`.as("count")])
    .groupBy("status")
    .execute();
  const pending = await db
    .selectFrom("publicationDrafts")
    .select(sql<number>`count(*)::integer`.as("count"))
    .where("status", "=", "pending")
    .executeTakeFirstOrThrow();
  const base: AdminState = {
    tracks: [],
    submissions: [],
    events: [],
    total: 0,
    page: input.page,
    stats: {
      published: count.find((r) => r.status === "published")?.count ?? 0,
      drafts: count.find((r) => r.status === "draft")?.count ?? 0,
      pending: pending.count,
    },
    recognition: {
      enabled: false,
      message:
        "Автораспознавание приостановлено. Редактирование и импорт готовых субтитров доступны.",
    },
  };
  const offset = (input.page - 1) * 20;
  if (input.section === "catalog") {
    let query = db.selectFrom("catalogTracks");
    if (input.status !== "all")
      query = query.where("status", "=", input.status);
    if (input.search)
      query = query.where((eb) =>
        eb.or([
          eb("title", "ilike", "%" + input.search + "%"),
          eb("artist", "ilike", "%" + input.search + "%"),
        ]),
      );
    base.total = Number(
      (
        await query
          .select(sql<number>`count(*)::integer`.as("count"))
          .executeTakeFirstOrThrow()
      ).count,
    );
    const rows = await query
      .select([
        "id",
        "title",
        "artist",
        "language",
        "duration",
        "audioUrl",
        "artworkUrl",
        "status",
        "revision",
        "captionsRevision",
        "captions",
        "updatedAt",
      ])
      .orderBy("createdAt", "desc")
      .orderBy("id")
      .offset(offset)
      .limit(20)
      .execute();
    base.tracks = rows.map((r) => ({
      ...r,
      captions: r.captions as unknown as Caption[],
      updatedAt: r.updatedAt.toISOString(),
    }));
  } else if (input.section === "submissions") {
    let query = db.selectFrom("publicationDrafts");
    if (input.status !== "all")
      query = query.where("status", "=", input.status);
    if (input.search)
      query = query.where((eb) =>
        eb.or([
          eb("title", "ilike", "%" + input.search + "%"),
          eb("artist", "ilike", "%" + input.search + "%"),
        ]),
      );
    base.total = Number(
      (
        await query
          .select(sql<number>`count(*)::integer`.as("count"))
          .executeTakeFirstOrThrow()
      ).count,
    );
    const rows = await query
      .select([
        "id",
        "title",
        "artist",
        "language",
        "status",
        "revision",
        "userId",
        "rejectionReason",
        "updatedAt",
      ])
      .orderBy("updatedAt", "desc")
      .orderBy("id")
      .offset(offset)
      .limit(20)
      .execute();
    base.submissions = rows.map((r) => ({
      ...r,
      updatedAt: r.updatedAt.toISOString(),
    }));
  } else if (input.section === "errors") {
    const result = await sql<{
      id: string;
      platform: string;
      version: string;
      build: string;
      area: string;
      errorType: string;
      errorCode: number;
      occurredAt: Date;
    }>`
      select id,platform,version,build,area,error_type,error_code,occurred_at from muwa_diagnostics
      where received_at>now()-interval '14 days' order by received_at desc,id desc offset ${offset} limit 20`.execute(
      db,
    );
    base.total = Number(
      (
        await sql<{
          count: string;
        }>`select count(*)::text as count from muwa_diagnostics where received_at>now()-interval '14 days'`.execute(
          db,
        )
      ).rows[0].count,
    );
    base.errors = result.rows.map((row) => ({
      ...row,
      occurredAt: row.occurredAt.toISOString(),
    }));
  } else {
    base.total = Number(
      (
        await db
          .selectFrom("adminAuditEvents")
          .select(sql<number>`count(*)::integer`.as("count"))
          .executeTakeFirstOrThrow()
      ).count,
    );
    const rows = await db
      .selectFrom("adminAuditEvents")
      .leftJoin("users", "users.id", "adminAuditEvents.actorId")
      .select([
        "adminAuditEvents.id",
        "action",
        "entityId",
        "users.displayName as actor",
        "adminAuditEvents.createdAt",
      ])
      .orderBy("adminAuditEvents.id", "desc")
      .offset(offset)
      .limit(20)
      .execute();
    base.events = rows.map((r) => ({
      ...r,
      id: String(r.id),
      createdAt: r.createdAt.toISOString(),
    }));
  }
  return base;
}
async function handle(request: Request, method: "GET" | "POST") {
  try {
    if (method === "POST") guardMutation(request);
    const { user, session } = await getServerUserSession(request);
    if (user.role !== "admin") fail("Доступ только администраторам Muwa.", 403);
    let output: AdminResult | AdminState;
    if (method === "POST") {
      await takeRateLimit(`admin-action:${user.id}`, 60, 60);
      const parsed = adminValidation.action.safeParse(
        await readJSONLimited(request, 2 * 1024 * 1024),
      );
      if (!parsed.success)
        fail(parsed.error.issues[0]?.message ?? "Проверьте данные.");
      if (
        (parsed.data.action === "lookup-telegram-import" ||
          parsed.data.action === "import-telegram-track") &&
        !telegramImportOwnerAllowed(user.id)
      )
        fail("Импорт из Telegram доступен только владельцу Muwa.", 403);
      output = await execute(parsed.data, user.id);
    } else {
      const parsed = adminValidation.query.safeParse(
        Object.fromEntries(new URL(request.url).searchParams),
      );
      if (!parsed.success) fail("Проверьте фильтры.");
      output = await state(parsed.data);
    }
    const response = json(output);
    await setServerSession(response, {
      ...session,
      lastAccessed: session.lastAccessed.getTime(),
    });
    return response;
  } catch (error) {
    if (error instanceof NotAuthenticatedError)
      return json({ error: "Войдите в аккаунт Muwa." }, 401);
    if (error instanceof SecurityError)
      return json({ error: error.message }, error.status);
    if (error instanceof SyntaxError)
      return json({ error: "Некорректный JSON." }, 400);
    console.error(
      "Muwa admin request failed",
      error instanceof Error ? error.name : "unknown",
    );
    return json({ error: "Сервис временно недоступен. Повторите позже." }, 503);
  }
}
export const adminService = { handle };
