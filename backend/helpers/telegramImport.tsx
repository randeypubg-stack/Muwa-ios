import { sql, type Transaction } from "kysely";
import { db } from "./db";
import type { DB } from "./schema";
import { SecurityError } from "./requestSecurity";

export type TelegramSource = {
  channelId: string;
  messageId: number;
  audioSha256?: string;
};
type Match = { trackId: string; audioSha256: string };

// No network calls while these transaction-scoped locks are held. Shared with
// ordinary catalogue saves so a manual upload and import cannot race the hash.
export async function lockAudio(tx: Transaction<DB>, sha256: string) {
  await sql`select pg_advisory_xact_lock(hashtextextended(${"muwa-audio:" + sha256},0))`.execute(
    tx,
  );
}
export async function lockTelegramSource(
  tx: Transaction<DB>,
  source: TelegramSource,
) {
  await sql`select pg_advisory_xact_lock(hashtextextended(${"muwa-telegram:" + source.channelId + ":" + source.messageId},0))`.execute(
    tx,
  );
}
export async function findTelegramSource(
  source: TelegramSource,
  connection: typeof db | Transaction<DB> = db,
) {
  const row = (
    await sql<Match>`select track_id,audio_sha256 from catalog_telegram_sources
    where channel_id=${source.channelId} and message_id=${source.messageId}`.execute(
      connection,
    )
  ).rows[0];
  if (!row) return null;
  if (source.audioSha256 && row.audioSha256 !== source.audioSha256)
    throw new SecurityError(
      "Аудио этого сообщения изменилось. Проверьте его в панели; импорт не перезаписывает нашид.",
      409,
    );
  return row.trackId;
}
export async function findAudioDuplicate(tx: Transaction<DB>, sha256: string) {
  // Lock the chosen track so a simultaneous manual audio replacement cannot
  // change the recording between hash lookup and source association.
  const id = (
    await sql<{ id: string }>`select t.id from catalog_tracks t
    join catalog_audio_fingerprints f on f.track_id=t.id where f.sha256=${sha256}
    order by (t.status='published') desc,t.created_at,t.id limit 1 for update of t`.execute(
      tx,
    )
  ).rows[0]?.id;
  if (!id) return null;
  // A replacement may commit while SELECT waits on its row. Re-read under
  // that lock with a fresh READ COMMITTED snapshot before linking a source.
  const current = (
    await sql<{
      sha256: string;
    }>`select sha256 from catalog_audio_fingerprints where track_id=${id}`.execute(
      tx,
    )
  ).rows[0];
  return current?.sha256 === sha256 ? id : null;
}
export async function rememberAudio(
  tx: Transaction<DB>,
  trackId: string,
  sha256: string,
) {
  await sql`insert into catalog_audio_fingerprints(track_id,sha256) values(${trackId},${sha256})
    on conflict(track_id) do update set sha256=excluded.sha256,updated_at=now()`.execute(
    tx,
  );
}
export async function rememberTelegramSource(
  tx: Transaction<DB>,
  source: TelegramSource & { audioSha256: string },
  trackId: string,
  userId: number,
) {
  await sql`insert into catalog_telegram_sources(channel_id,message_id,audio_sha256,track_id,imported_by)
    values(${source.channelId},${source.messageId},${source.audioSha256},${trackId},${userId})`.execute(
    tx,
  );
}
