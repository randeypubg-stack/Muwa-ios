import { randomUUID } from "node:crypto";
import { sql } from "kysely";
import { db } from "./db";
import { SecurityError } from "./requestSecurity";
const MB = 1024 * 1024;
export const uploadPolicy = {
  regular: {
    dailyBytes: 512 * MB,
    totalBytes: 1024 * MB,
    activeDrafts: 5,
    requestsPerHour: 30,
  },
  admin: {
    dailyBytes: 5 * 1024 * MB,
    totalBytes: 20 * 1024 * MB,
    activeDrafts: 100,
    requestsPerHour: 200,
  },
};
export async function takeRateLimit(
  bucket: string,
  cap: number,
  seconds: number,
): Promise<void> {
  const result =
    await sql`insert into muwa_request_limits(bucket,attempts) values(${bucket},1)
    on conflict(bucket) do update set
      attempts=case when muwa_request_limits.window_start <= now()-(${seconds} * interval '1 second') then 1 else muwa_request_limits.attempts+1 end,
      window_start=case when muwa_request_limits.window_start <= now()-(${seconds} * interval '1 second') then now() else muwa_request_limits.window_start end,
      updated_at=now()
    where muwa_request_limits.window_start <= now()-(${seconds} * interval '1 second') or muwa_request_limits.attempts<${cap}
    returning bucket`.execute(db);
  if (!result.rows.length)
    throw new SecurityError("Слишком много запросов. Повторите позже.", 429);
}
export type PublicationUpload = {
  draftId: string;
  part: "audio" | "cover" | "submission";
  contentType: string;
  sizeBytes: number;
  sha256?: string;
};
const extension: Record<string, string> = {
  "audio/mpeg": "mp3",
  "audio/mp4": "m4a",
  "audio/x-m4a": "m4a",
  "audio/wav": "wav",
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "application/json": "json",
};
export async function reservePublication(
  userId: number,
  isAdmin: boolean,
  input: PublicationUpload,
) {
  const policy = isAdmin ? uploadPolicy.admin : uploadPolicy.regular;
  await takeRateLimit(`publication:${userId}`, policy.requestsPerHour, 3600);
  return db.transaction().execute(async (tx) => {
    await tx
      .selectFrom("users")
      .select("id")
      .where("id", "=", userId)
      .forUpdate()
      .executeTakeFirstOrThrow();
    const existing = await tx
      .selectFrom("publicationDrafts")
      .select(["userId", "status"])
      .where("id", "=", input.draftId)
      .executeTakeFirst();
    if (existing && existing.userId !== userId)
      throw new SecurityError("Черновик недоступен для загрузки.", 403);
    if (!existing) {
      const active = await tx
        .selectFrom("publicationDrafts")
        .select(sql<number>`count(*)::integer`.as("count"))
        .where("userId", "=", userId)
        .where("status", "in", ["uploading", "pending"])
        .executeTakeFirstOrThrow();
      if (active.count >= policy.activeDrafts)
        throw new SecurityError(
          "Сначала завершите или дождитесь проверки предыдущих публикаций.",
          429,
        );
      await tx
        .insertInto("publicationDrafts")
        .values({ id: input.draftId, userId })
        .execute();
    }
    const previous = await sql<{
      filename: string;
      sizeBytes: string;
      expectedSha256: string | null;
    }>`
      select filename,size_bytes,expected_sha256 from publication_uploads where draft_id=${input.draftId} and part=${input.part} and deleted_at is null order by created_at desc limit 1`.execute(
      tx,
    );
    const prior = previous.rows[0];
    if (
      prior &&
      input.sha256 &&
      prior.expectedSha256 === input.sha256 &&
      Number(prior.sizeBytes) === input.sizeBytes
    )
      return { filename: prior.filename, reused: true };
    if (existing && existing.status !== "uploading")
      throw new SecurityError("Публикация уже отправлена на проверку.", 409);
    const ready =
      await sql`select id from publication_uploads where draft_id=${input.draftId} and part='submission' and deleted_at is null limit 1`.execute(
        tx,
      );
    if (ready.rows.length)
      throw new SecurityError(
        "Данные отправленной публикации нельзя изменять. Создайте новый черновик.",
        409,
      );
    const budget = await sql<{ total: string; daily: string }>`select
      coalesce(sum(size_bytes) filter(where deleted_at is null),0)::text as total,
      coalesce(sum(size_bytes) filter(where created_at>now()-interval '24 hours'),0)::text as daily
      from publication_uploads where user_id=${userId}`.execute(tx);
    if (
      Number(budget.rows[0].total) + input.sizeBytes > policy.totalBytes ||
      Number(budget.rows[0].daily) + input.sizeBytes > policy.dailyBytes
    )
      throw new SecurityError(
        "Достигнут лимит объёма загрузок. Повторите позже.",
        429,
      );
    const id = randomUUID();
    const filename =
      input.part === "submission"
        ? `publications/${input.draftId}/submission.json`
        : `publications/${input.draftId}/${input.part}-${id}.${extension[input.contentType]}`;
    await sql`insert into publication_uploads(id,draft_id,user_id,part,filename,content_type,size_bytes,expected_sha256,expires_at)
      values(${id},${input.draftId},${userId},${input.part},${filename},${input.contentType},${input.sizeBytes},${input.sha256 ?? null},now()+interval '15 minutes')`.execute(
      tx,
    );
    await tx
      .updateTable("publicationDrafts")
      .set({
        updatedAt: new Date(),
        ...(input.part === "audio"
          ? { audioKey: filename }
          : input.part === "cover"
            ? { coverKey: filename }
            : {}),
      })
      .where("id", "=", input.draftId)
      .execute();
    return { filename, reused: false };
  });
}
export async function reserveCatalog(
  userId: number,
  id: string,
  files: unknown[],
  sizeBytes: number,
  trackId?: string,
  submissionId?: string,
) {
  await takeRateLimit(
    `catalog-upload:${userId}`,
    uploadPolicy.admin.requestsPerHour,
    3600,
  );
  await db.transaction().execute(async (tx) => {
    await tx
      .selectFrom("users")
      .select("id")
      .where("id", "=", userId)
      .forUpdate()
      .executeTakeFirstOrThrow();
    const usage = await sql<{ daily: string; total: string }>`select
      coalesce(sum((f->>'sizeBytes')::bigint) filter(where u.created_at>now()-interval '24 hours'),0)::text as daily,
      coalesce(sum((f->>'sizeBytes')::bigint) filter(where u.deleted_at is null),0)::text as total
      from catalog_uploads u cross join lateral jsonb_array_elements(u.files) f where u.user_id=${userId}`.execute(
      tx,
    );
    if (
      Number(usage.rows[0].daily) + sizeBytes > uploadPolicy.admin.dailyBytes ||
      Number(usage.rows[0].total) + sizeBytes > uploadPolicy.admin.totalBytes
    )
      throw new SecurityError("Достигнут лимит объёма загрузок.", 429);
    await tx
      .insertInto("catalogUploads")
      .values({
        id,
        userId,
        trackId: trackId ?? null,
        submissionId: submissionId ?? null,
        files: files as never,
        expiresAt: new Date(Date.now() + 15 * 60 * 1000),
      })
      .execute();
  });
}
export function validPublicationKey(
  key: string,
  draftId: string,
  part: "audio" | "cover",
) {
  return new RegExp(
    `^publications/${draftId}/${part}(?:-[0-9a-f-]{36})?\\.(mp3|m4a|wav|jpg|png|webp)$`,
    "i",
  ).test(key);
}
