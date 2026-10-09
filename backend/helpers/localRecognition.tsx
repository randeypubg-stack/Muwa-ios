import { sql, type Transaction } from "kysely";
import { db } from "./db";
import type { DB } from "./schema";
import type {
  RecognitionCounts,
  RecognitionResult,
  RecognitionSummary,
} from "./adminValidation";
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
      and j.language=muwa_asr_language(t.language)
      and j.status<>'stale'`.execute(db);
  return r.rows;
}
export function recognitionSummary(r: RecognitionResult): RecognitionSummary {
  const { document, trackId, ...summary } = r;
  return summary;
}

export async function recognitionCounts(): Promise<
  RecognitionCounts | undefined
> {
  if (!localRecognitionEnabled()) return undefined;
  // Match only the current audio hash, file and language. Old recognition must
  // not make a replaced recording appear ready. No full transcript is fetched.
  const result = await sql<RecognitionCounts>`
    select count(*) filter (where j.status='queued')::integer as queued,
      count(*) filter (where j.status='processing')::integer as processing,
      count(*) filter (where j.status='ready' and not coalesce((j.quality->>'needsReview')::boolean,true))::integer as ready,
      count(*) filter (where j.status='ready' and coalesce((j.quality->>'needsReview')::boolean,true))::integer as review,
      count(*) filter (where j.status='failed')::integer as failed,
      count(*) filter (where j.id is null)::integer as missing
    from catalog_tracks t
    join catalog_audio_fingerprints h on h.track_id=t.id
    left join catalog_asr_jobs j on j.track_id=t.id and j.audio_sha256=h.sha256
      and j.audio_filename=t.audio_filename and j.language=muwa_asr_language(t.language)
      and j.status<>'stale'
    where t.status<>'archived' and t.duration>0 and t.duration<=3600
      and t.audio_filename ~ '^catalog/[a-f0-9-]{36}/audio\\.(mp3|m4a|wav)$'
  `.execute(db);
  return result.rows[0];
}
