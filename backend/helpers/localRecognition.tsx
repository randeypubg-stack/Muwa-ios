import { sql, type Transaction } from "kysely";
import { db } from "./db";
import type { DB } from "./schema";
import type { RecognitionResult, RecognitionSummary } from "./adminValidation";
export function localRecognitionEnabled() {
  return process.env.MUWA_LOCAL_ASR_ENABLED === "1";
}
export async function enqueueRecognition(
  tx: Transaction<DB>,
  id: string,
  retry = false,
) {
  if (!localRecognitionEnabled()) return null;
  const r = await sql<{
    id: string | null;
  }>`select muwa_enqueue_asr(${id},${retry}) as id`.execute(tx);
  return r.rows[0]?.id ?? null;
}
export async function recognitionResults(
  ids: string[],
  documents = false,
): Promise<RecognitionResult[]> {
  if (!localRecognitionEnabled() || !ids.length) return [];
  const r = await sql<RecognitionResult>`
    select j.id,j.track_id,j.status,j.progress_seconds,j.error_code,
      j.document->>'language' as language,j.quality,
      ${documents ? sql`j.document` : sql`null::jsonb`} as document
    from catalog_asr_jobs j join catalog_tracks t on t.id=j.track_id
    join catalog_audio_fingerprints h on h.track_id=t.id and h.sha256=j.audio_sha256
    where j.track_id in (${sql.join(ids)}) and j.audio_filename=t.audio_filename
      and j.language=case when lower(t.language) ~ '^[a-z]{2,3}$' then lower(t.language) else 'und' end
      and j.status<>'stale'`.execute(db);
  return r.rows;
}
export function recognitionSummary(r: RecognitionResult): RecognitionSummary {
  const { document, trackId, ...summary } = r;
  return summary;
}
