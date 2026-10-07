# Muwa local subtitle recognition

The owner resumed recognition on 7 October 2026. Upload/publication and Telegram
imports keep their existing contracts and never wait for the model. No paid ASR
or translation provider is enabled.

## Pipeline

1. The existing upload transaction verifies bytes and stores an audio SHA-256.
   `enqueueRecognition` adds one job per track, fingerprint and language.
2. One local worker claims a renewable PostgreSQL lease. Original-language
   Whisper large-v3 runs on CPU with int8 weights and beam size 5.
3. A constrained ffmpeg subprocess decodes local MP3/M4A/WAV into mono 16 kHz
   PCM. No uploaded playlist, remote URL, model code or text prompt is executed.
4. The worker preserves original text, phrase timings and valid estimated word
   timings. It does not create translations or rewrite religious wording.
5. Results and quality warnings are saved in the queue. Confident AR/RU/EN
   results also populate ordinary subtitles if the caption revision is still
   unchanged and no manual captions exist. They do not publish the track.
6. Uncertain output remains available in the owner's caption editor for review.
   Manual changes made while inference runs are never overwritten. Replaced
   audio and previous lease tokens cannot accept stale results.

Automatic subtitles are labelled `source: automatic`. Acoustic/model confidence
is not a word-error-rate measurement. Singing, chorus, reverberation, dialect and
recording quality can cause errors. Compare representative nasheeds against
human-reviewed lyrics before claiming accuracy. Full large-v3 on a 2-core/4-GiB
VPS is a background/beta solution, not a high-throughput transcription cluster.
The service limits itself to one CPU, 3000 MiB RAM and 1000 MiB swap.

## Deployment

- Install `requirements.txt` in `/opt/muwa/asr/venv`; the tested runtime uses
  Python 3.14. Never install model/worker dependencies in the API environment.
- Download only the five required assets from
  `Systran/faster-whisper-large-v3`, revision
  `edaa852ec7e145841d8ffdb056a99866b5f0a478`, into
  `/opt/muwa/asr/models/large-v3`. Record sizes/SHA-256. No remote model scripts.
- Apply `backend/asr-migration.sql` after the admin/security/Telegram migrations,
  owned by the existing `muwa_owner` role. Preserve existing users and media.
- The API role needs table access to `catalog_asr_jobs` and execute on
  `muwa_enqueue_asr(text,boolean)`. Set `MUWA_LOCAL_ASR_ENABLED=1` only after
  migrations, model, worker and compatibility checks succeed.
- Provision the OS user and matching PostgreSQL login role `muwa-asr`, using
  local Unix-socket **peer authentication**, no password. Grant only schema usage,
  database connect and execute on `muwa_claim_asr`, `muwa_heartbeat_asr`,
  `muwa_finish_asr`, `muwa_fail_asr`. No direct table, account, code-admin or
  enqueue privileges.
- Use a private `muwa-media` group for the API and ASR worker. Media directories
  are setgid `2750`, objects `0640`, no access to others. Set the API service's
  umask to `0027` and supplementary group to `muwa-media` so new objects retain
  that read permission. Secret files and importer state remain unchanged.
- Place `worker.py`/`transcript.py` under `/opt/muwa/asr`, create
  `/var/lib/muwa-asr` with `0700`, install `muwa-asr.service`. The installed
  model/runtime paths must be readable/traversable by the dedicated worker.
- The worker has no Internet address families or inbound ports. Model download
  is a separate provisioning operation; runtime uses local files only.
- Backfill the existing catalog with `muwa_enqueue_asr(id)` once. Subsequent
  uploads queue automatically. Failed jobs can be retried only by the owner
  through the existing panel action. Crash recovery stops after three attempts.
- Use a daily tmpfiles rule to clear abandoned worker temporary files older
  than one day; a single inference is terminated after three hours.

Monitor `systemctl status muwa-asr` and fixed event codes in the journal. No
passwords, tokens, source paths or transcript bodies are logged. Stop recognition
without affecting audio: `systemctl stop muwa-asr` and disable the API feature
flag. PostgreSQL/media backups already include generated documents and captions.

## Checks

`PYTHONPATH=tools/local-asr python -m unittest discover -s tools/local-asr/tests`
tests text/timing validation and decoder/path/hash boundaries. Backend DB checks
exercise real PostgreSQL leases, automatic enqueue, concurrent claims, owner
access, malformed documents, stale recordings and manual-edit protection.
Run an actual nasheed separately; test fixtures cannot prove speech accuracy.
