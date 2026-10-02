import { sql } from "kysely";
import { remove, getInfo } from "@floot/storage";
import { db } from "./db";
import { SecurityError } from "./requestSecurity";
type File = { filename: string; visibility?: "private" | "public" };
async function removeStoredFile(
  visibility: "private" | "public",
  filename: string,
) {
  const info = await getInfo({ visibility, filename });
  if (!info.ok) throw new SecurityError("Хранилище недоступно.", 503);
  if (info.exists && !(await remove({ visibility, filename })).ok)
    throw new SecurityError(
      "Не удалось очистить хранилище. Повторите позже.",
      503,
    );
}
export async function cleanupExpiredUploads(actorId: number) {
  let removed = 0;
  const plans = await sql<{
    id: string;
    userId: number;
  }>`select id,user_id from catalog_uploads where consumed_at is null and deleted_at is null and expires_at<now()-interval '24 hours' order by expires_at limit 10`.execute(
    db,
  );
  for (const plan of plans.rows)
    await db.transaction().execute(async (tx) => {
      await tx
        .selectFrom("users")
        .select("id")
        .where("id", "=", plan.userId)
        .forUpdate()
        .executeTakeFirstOrThrow();
      const current = await sql<{
        files: File[];
      }>`select files from catalog_uploads where id=${plan.id} and consumed_at is null and deleted_at is null and expires_at<now()-interval '24 hours' for update`.execute(
        tx,
      );
      if (!current.rows.length) return;
      for (const file of current.rows[0].files) {
        if (
          !/^catalog\/[0-9a-f-]{36}\/(audio|cover)\.(mp3|m4a|wav|jpg|png|webp)$/.test(
            file.filename,
          )
        )
          continue;
        const references =
          await sql`select id from catalog_tracks where audio_filename=${file.filename} or cover_filename=${file.filename} limit 1`.execute(
            tx,
          );
        if (references.rows.length) continue;
        await removeStoredFile(file.visibility ?? "public", file.filename);
        removed++;
      }
      await sql`update catalog_uploads set deleted_at=now() where id=${plan.id}`.execute(
        tx,
      );
    });
  const drafts = await db
    .selectFrom("publicationDrafts")
    .select(["id", "userId"])
    .where("status", "=", "uploading")
    .where("updatedAt", "<", new Date(Date.now() - 48 * 3600000))
    .limit(10)
    .execute();
  for (const draft of drafts)
    if (draft.userId)
      await db.transaction().execute(async (tx) => {
        await tx
          .selectFrom("users")
          .select("id")
          .where("id", "=", draft.userId!)
          .forUpdate()
          .executeTakeFirstOrThrow();
        const row = await tx
          .selectFrom("publicationDrafts")
          .selectAll()
          .where("id", "=", draft.id)
          .forUpdate()
          .executeTakeFirstOrThrow();
        if (
          row.status !== "uploading" ||
          row.updatedAt >= new Date(Date.now() - 48 * 3600000)
        )
          return;
        const leases = await sql<{
          filename: string;
        }>`select filename from publication_uploads where draft_id=${draft.id} and deleted_at is null and expires_at<now()-interval '24 hours'`.execute(
          tx,
        );
        for (const lease of leases.rows) {
          if (!lease.filename.startsWith(`publications/${draft.id}/`)) continue;
          await removeStoredFile("private", lease.filename);
          await sql`update publication_uploads set deleted_at=now() where filename=${lease.filename}`.execute(
            tx,
          );
          removed++;
        }
        await tx
          .updateTable("publicationDrafts")
          .set({
            status: "rejected",
            rejectionReason: "Незавершённая загрузка удалена после 48 часов.",
            revision: row.revision + 1,
            updatedAt: new Date(),
          })
          .where("id", "=", draft.id)
          .execute();
        await tx
          .insertInto("adminAuditEvents")
          .values({ actorId, action: "submission.expired", entityId: draft.id })
          .execute();
      });
  // Retries may leave obsolete versions inside an otherwise completed draft.
  // Recheck the account and current references under the same upload lock.
  const obsolete = await sql<{
    id: string;
    draftId: string;
    userId: number;
    filename: string;
  }>`
    select u.id,u.draft_id,u.user_id,u.filename from publication_uploads u join publication_drafts d on d.id=u.draft_id
    where u.deleted_at is null and u.part in ('audio','cover') and u.expires_at<now()-interval '24 hours'
      and u.filename is distinct from d.audio_key and u.filename is distinct from d.cover_key
    order by u.expires_at limit 20`.execute(db);
  for (const lease of obsolete.rows)
    await db.transaction().execute(async (tx) => {
      await tx
        .selectFrom("users")
        .select("id")
        .where("id", "=", lease.userId)
        .forUpdate()
        .executeTakeFirstOrThrow();
      const current = await tx
        .selectFrom("publicationDrafts")
        .select(["audioKey", "coverKey", "userId"])
        .where("id", "=", lease.draftId)
        .forUpdate()
        .executeTakeFirstOrThrow();
      if (
        current.userId !== lease.userId ||
        [current.audioKey, current.coverKey].includes(lease.filename)
      )
        return;
      const available =
        await sql`select id from publication_uploads where id=${lease.id} and deleted_at is null and expires_at<now()-interval '24 hours'`.execute(
          tx,
        );
      if (
        !available.rows.length ||
        !lease.filename.startsWith(`publications/${lease.draftId}/`)
      )
        return;
      await removeStoredFile("private", lease.filename);
      await sql`update publication_uploads set deleted_at=now() where id=${lease.id}`.execute(
        tx,
      );
      removed++;
    });
  await sql`delete from muwa_request_limits where updated_at<now()-interval '7 days'`.execute(
    db,
  );
  return { ok: true as const, removed };
}
