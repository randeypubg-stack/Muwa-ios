-- Additive local recognition queue. Apply after telegram-import-migration.sql.
ALTER TABLE catalog_tracks ADD COLUMN IF NOT EXISTS captions_source text NOT NULL DEFAULT 'manual'
 CHECK (captions_source IN ('manual','automatic'));
CREATE TABLE IF NOT EXISTS catalog_asr_jobs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 track_id text NOT NULL REFERENCES catalog_tracks(id) ON DELETE CASCADE,
 audio_filename text NOT NULL CHECK (audio_filename ~ '^catalog/[a-f0-9-]{36}/audio\.(mp3|m4a|wav)$'),
 audio_sha256 text NOT NULL CHECK (audio_sha256 ~ '^[a-f0-9]{64}$'),
 language text NOT NULL CHECK (language ~ '^[a-z]{2,3}$'),
 duration double precision NOT NULL CHECK (duration > 0 AND duration <= 3600),
 captions_revision integer NOT NULL,
 status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','processing','ready','failed','stale')),
 attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
 lease_token uuid, lease_until timestamptz,
 progress_seconds double precision NOT NULL DEFAULT 0 CHECK (progress_seconds >= 0 AND progress_seconds <= 3600),
 document jsonb, quality jsonb, error_code text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(track_id,audio_sha256,language)
);
CREATE INDEX IF NOT EXISTS catalog_asr_jobs_queue_idx ON catalog_asr_jobs(created_at,id)
 WHERE status IN ('queued','processing');
CREATE INDEX IF NOT EXISTS catalog_asr_jobs_track_idx ON catalog_asr_jobs(track_id);

-- Called inside the same transaction as saving/fingerprinting an upload.
-- Whisper uses the Arabic language token for MSA and dialects, not separate
-- dialect models. Keep the catalogue's regional tag but decode the original
-- Arabic words; do not run translation or infer a dialect from the title.
CREATE OR REPLACE FUNCTION muwa_asr_language(p_language text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT CASE
  WHEN lower(p_language) ~ '^ar([_-][a-z0-9]{2,8})*$'
    OR lower(p_language) IN ('aao','abh','abv','acm','acq','acw','acx','acy','adf','aeb','aec','afb','ajp','apc','apd','arb','arq','ars','ary','arz','auz','avl','ayh','ayl','ayn','ayp','pga','shu','ssh') THEN 'ar'
  WHEN lower(p_language) ~ '^[a-z]{2,3}$' THEN lower(p_language)
  ELSE 'und' END;
$$;
CREATE OR REPLACE FUNCTION muwa_enqueue_asr(p_track text,p_retry boolean DEFAULT false)
RETURNS uuid LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
DECLARE t public.catalog_tracks; h text; job uuid; lang text;
BEGIN
 SELECT * INTO t FROM public.catalog_tracks WHERE id=p_track FOR UPDATE;
 IF NOT FOUND OR t.audio_filename IS NULL OR t.audio_filename !~ '^catalog/[a-f0-9-]{36}/audio\.(mp3|m4a|wav)$'
   OR t.duration <= 0 OR t.duration > 3600 THEN RETURN NULL; END IF;
 lang := public.muwa_asr_language(t.language);
 SELECT sha256 INTO h FROM public.catalog_audio_fingerprints WHERE track_id=t.id;
 IF h IS NULL THEN RETURN NULL; END IF;
 UPDATE public.catalog_asr_jobs SET status='stale',lease_token=NULL,lease_until=NULL,updated_at=now()
 WHERE track_id=t.id AND (audio_sha256<>h OR audio_filename<>t.audio_filename OR language<>lang) AND status<>'stale';
 INSERT INTO public.catalog_asr_jobs(track_id,audio_filename,audio_sha256,language,duration,captions_revision)
 VALUES(t.id,t.audio_filename,h,lang,t.duration,t.captions_revision)
 ON CONFLICT(track_id,audio_sha256,language) DO UPDATE SET
   audio_filename=excluded.audio_filename,duration=excluded.duration,captions_revision=excluded.captions_revision,
   status='queued',attempts=0,lease_token=NULL,lease_until=NULL,document=NULL,quality=NULL,error_code=NULL,
   progress_seconds=0,updated_at=now()
 WHERE catalog_asr_jobs.status='stale' OR (p_retry AND catalog_asr_jobs.status IN ('ready','failed'))
 RETURNING id INTO job;
 IF job IS NULL THEN SELECT id INTO job FROM public.catalog_asr_jobs WHERE track_id=t.id AND audio_sha256=h AND language=lang; END IF;
 RETURN job;
END $$;

-- Workers receive no table permissions, owner password or storage-signing key.
CREATE OR REPLACE FUNCTION muwa_claim_asr(p_token uuid)
RETURNS SETOF catalog_asr_jobs LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF NOT pg_try_advisory_xact_lock(746291,1) THEN RETURN; END IF;
 UPDATE public.catalog_asr_jobs SET status='failed',error_code='LEASE_EXPIRED',lease_token=NULL,lease_until=NULL,updated_at=now()
 WHERE status='processing' AND lease_until<now() AND attempts>=3;
 IF EXISTS(SELECT 1 FROM public.catalog_asr_jobs WHERE status='processing' AND lease_until>now()) THEN RETURN; END IF;
 RETURN QUERY UPDATE public.catalog_asr_jobs j SET status='processing',attempts=j.attempts+1,
 lease_token=p_token,lease_until=now()+interval '90 seconds',updated_at=now(),error_code=NULL,progress_seconds=0
 WHERE j.id=(
   SELECT q.id FROM public.catalog_asr_jobs q
   JOIN public.catalog_tracks t ON t.id=q.track_id AND t.audio_filename=q.audio_filename
   JOIN public.catalog_audio_fingerprints h ON h.track_id=t.id AND h.sha256=q.audio_sha256
   WHERE (q.status='queued' OR (q.status='processing' AND q.lease_until<now() AND q.attempts<3))
    AND q.language=public.muwa_asr_language(t.language)
   ORDER BY q.created_at,q.id LIMIT 1 FOR UPDATE OF q SKIP LOCKED
 ) RETURNING j.*;
END $$;
CREATE OR REPLACE FUNCTION muwa_heartbeat_asr(p_id uuid,p_token uuid,p_progress double precision)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 WITH renewed AS (UPDATE public.catalog_asr_jobs SET lease_until=now()+interval '90 seconds',
 progress_seconds=greatest(progress_seconds,least(duration,greatest(0,p_progress))),updated_at=now()
 WHERE id=p_id AND status='processing' AND lease_token=p_token AND lease_until>now()
 AND p_progress>=0 AND p_progress<=3600 RETURNING 1) SELECT EXISTS(SELECT 1 FROM renewed);
$$;
CREATE OR REPLACE FUNCTION muwa_fail_asr(p_id uuid,p_token uuid,p_code text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 WITH failed AS (UPDATE public.catalog_asr_jobs SET status='failed',error_code=p_code,
 lease_token=NULL,lease_until=NULL,updated_at=now()
 WHERE id=p_id AND status='processing' AND lease_token=p_token AND lease_until>now()
 AND p_code IN ('INVALID_AUDIO','NO_SPEECH','INVALID_TRANSCRIPT','INFERENCE_FAILED','JOB_TIMEOUT','AUDIO_CHANGED','DISK_FULL')
 RETURNING 1) SELECT EXISTS(SELECT 1 FROM failed);
$$;
CREATE OR REPLACE FUNCTION muwa_finish_asr(p_id uuid,p_token uuid,p_doc jsonb,p_quality jsonb)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE j public.catalog_asr_jobs; t public.catalog_tracks; h text; lines jsonb; lang text;
BEGIN
 SELECT * INTO j FROM public.catalog_asr_jobs WHERE id=p_id;
 IF NOT FOUND THEN RETURN false; END IF;
 -- Same lock order as the API: track, then job. Never hold a DB transaction during inference.
 SELECT * INTO t FROM public.catalog_tracks WHERE id=j.track_id FOR UPDATE;
 SELECT * INTO j FROM public.catalog_asr_jobs WHERE id=p_id FOR UPDATE;
 IF NOT FOUND OR j.status<>'processing' OR j.lease_token IS DISTINCT FROM p_token OR j.lease_until IS NULL OR j.lease_until<=now() THEN RETURN false; END IF;
 SELECT sha256 INTO h FROM public.catalog_audio_fingerprints WHERE track_id=t.id;
 IF h IS DISTINCT FROM j.audio_sha256 OR t.audio_filename IS DISTINCT FROM j.audio_filename OR
   public.muwa_asr_language(t.language)<>j.language THEN
  UPDATE public.catalog_asr_jobs SET status='stale',lease_token=NULL,lease_until=NULL,updated_at=now() WHERE id=p_id;
  RETURN false;
 END IF;
 lang := p_doc->>'language';
 IF octet_length(p_doc::text)>2097152 OR p_doc->>'version' IS DISTINCT FROM '2' OR p_doc->>'id' IS DISTINCT FROM p_id::text
 OR lang IS NULL OR lang !~ '^[a-z]{2,3}$' OR jsonb_typeof(p_doc->'segments') IS DISTINCT FROM 'array'
 OR jsonb_typeof(p_quality->'needsReview') IS DISTINCT FROM 'boolean' OR octet_length(p_quality::text)>8192 THEN
  RAISE EXCEPTION 'INVALID_TRANSCRIPT'; END IF;
 IF jsonb_array_length(p_doc->'segments') NOT BETWEEN 1 AND 600 THEN RAISE EXCEPTION 'INVALID_TRANSCRIPT'; END IF;
 IF j.language<>'und' AND lang<>j.language THEN RAISE EXCEPTION 'INVALID_TRANSCRIPT'; END IF;
 IF EXISTS(
  SELECT 1 FROM (
   SELECT s,ord,lag((s->>'end')::double precision) OVER(ORDER BY ord) AS previous_end
   FROM jsonb_array_elements(p_doc->'segments') WITH ORDINALITY a(s,ord)
  ) r WHERE jsonb_typeof(s->'start') IS DISTINCT FROM 'number' OR jsonb_typeof(s->'end') IS DISTINCT FROM 'number'
  OR jsonb_typeof(s->'original') IS DISTINCT FROM 'string' OR length(trim(s->>'original')) NOT BETWEEN 1 AND 1200
  OR (s->>'start')::double precision<0 OR (s->>'end')::double precision<=(s->>'start')::double precision
  OR (s->>'end')::double precision>t.duration+0.1 OR (s->>'start')::double precision<previous_end
 ) THEN RAISE EXCEPTION 'INVALID_TRANSCRIPT'; END IF;
 UPDATE public.catalog_asr_jobs SET status='ready',document=p_doc,quality=p_quality,error_code=NULL,
 progress_seconds=duration,lease_token=NULL,lease_until=NULL,updated_at=now() WHERE id=p_id;
 IF lang IN ('ar','ru','en') AND p_quality->>'needsReview'='false' AND t.captions_revision=j.captions_revision
 AND ((t.captions='[]'::jsonb AND t.captions_revision=0) OR t.captions_source='automatic') THEN
  SELECT jsonb_agg(jsonb_build_object('start',s->'start','end',s->'end',
   'ar',CASE WHEN lang='ar' THEN s->>'original' ELSE '' END,
   'ru',CASE WHEN lang='ru' THEN s->>'original' ELSE '' END,
   'en',CASE WHEN lang='en' THEN s->>'original' ELSE '' END,'words',s->'words') ORDER BY ord) INTO lines
  FROM jsonb_array_elements(p_doc->'segments') WITH ORDINALITY a(s,ord);
  UPDATE public.catalog_tracks SET captions=lines,captions_source='automatic',captions_revision=captions_revision+1,
   revision=revision+1,updated_at=now() WHERE id=t.id;
 END IF;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION muwa_enqueue_asr(text,boolean),muwa_claim_asr(uuid),
 muwa_heartbeat_asr(uuid,uuid,double precision),muwa_fail_asr(uuid,uuid,text),muwa_finish_asr(uuid,uuid,jsonb,jsonb) FROM PUBLIC;
-- Deployment grants enqueue to the existing API role, and only the four worker
-- functions to a separate local, non-superuser role. No role/account changes here.
