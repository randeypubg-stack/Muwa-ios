"""Single local CPU worker. No cloud ASR, owner credentials or inbound listener."""
import hashlib
import json
import logging
import math
import multiprocessing
import os
from pathlib import Path
import signal
import shutil
import stat
import subprocess
import tempfile
import threading
import time
import uuid
import wave

import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb
from transcript import normalize, TranscriptError

DSN = 'dbname=muwa user=muwa-asr host=/var/run/postgresql connect_timeout=10'
INPUT_POLICY = ['-protocol_whitelist', 'file,pipe', '-format_whitelist', 'mp3,wav,mov', '-max_alloc', '33554432']
DECODER_ENV = {'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8', 'LC_ALL': 'C.UTF-8'}


def connect():
    return psycopg.connect(DSN, autocommit=True, row_factory=dict_row)


def sql_call(name, args):
    # Identifiers are fixed by this module, never derived from an upload.
    statements = {
        'heartbeat': 'SELECT muwa_heartbeat_asr(%s,%s,%s) AS ok',
        'finish': 'SELECT muwa_finish_asr(%s,%s,%s,%s) AS ok',
        'fail': 'SELECT muwa_fail_asr(%s,%s,%s) AS ok',
    }
    with connect() as db:
        return db.execute(statements[name], args).fetchone()['ok']


def source_file(root, filename, digest):
    import re
    if not re.fullmatch(r'catalog/[a-f0-9-]{36}/audio\.(mp3|m4a|wav)', filename):
        raise TranscriptError('INVALID_AUDIO')
    path = Path(root)
    for part in filename.split('/'):
        path = path / part
        if path.is_symlink():
            raise TranscriptError('INVALID_AUDIO')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= 100 * 1024 * 1024:
            raise TranscriptError('INVALID_AUDIO')
        if hashlib.file_digest(stream, 'sha256').hexdigest() != digest:
            raise TranscriptError('AUDIO_CHANGED')
    return path


def decode(path, target):
    # Only a constrained ffmpeg subprocess reads untrusted compressed media;
    # the model receives plain, mono 16 kHz PCM, never nested/network URLs.
    try:
        probe = subprocess.run(['ffprobe', '-v', 'error', *INPUT_POLICY, '-show_format', '-show_streams', '-of', 'json', str(path)],
                               env=DECODER_ENV, capture_output=True, timeout=30, check=True)
        info = json.loads(probe.stdout)
        duration = float(info['format']['duration'])
        if (not math.isfinite(duration) or not 0 < duration <= 3600
                or not any(s.get('codec_type') == 'audio' for s in info['streams'])):
            raise TranscriptError('INVALID_AUDIO')
        subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-y', *INPUT_POLICY, '-i', str(path), '-map', '0:a:0',
                        '-vn', '-threads', '1', '-ac', '1', '-ar', '16000', '-t', '3600.1', '-c:a', 'pcm_s16le', str(target)],
                       env=DECODER_ENV, capture_output=True, timeout=180, check=True)
        if not 0 < target.stat().st_size <= 116 * 1024 * 1024:
            raise TranscriptError('INVALID_AUDIO')
        return duration
    except (subprocess.SubprocessError, KeyError, ValueError, OSError) as error:
        if isinstance(error, TranscriptError):
            raise
        raise TranscriptError('INVALID_AUDIO') from None


def infer(model_path, pcm, language, job_id, duration, progress):
    from faster_whisper import WhisperModel
    import numpy as np
    # Full large-v3 rather than the reduced turbo model. No synthetic transcript prompt.
    model = WhisperModel(model_path, device='cpu', compute_type='int8', cpu_threads=1,
                         num_workers=1, local_files_only=True)
    # ffmpeg has already decoded the input. Do not decode it a second time via
    # PyAV's version-dependent container API; ndarray input is supported by Whisper.
    with wave.open(str(pcm), 'rb') as stream:
        if stream.getnchannels()!=1 or stream.getsampwidth()!=2 or stream.getframerate()!=16000 or stream.getnframes()>57601600:
            raise TranscriptError('INVALID_AUDIO')
        samples=np.frombuffer(stream.readframes(stream.getnframes()), dtype=np.dtype('<i2')).astype(np.float32) / 32768.0
    segments, info = model.transcribe(samples, language=None if language == 'und' else language,
                                     task='transcribe', beam_size=5, temperature=0,
                                     word_timestamps=True, vad_filter=False, condition_on_previous_text=False,
                                     no_speech_threshold=0.6, log_prob_threshold=-1.0, compression_ratio_threshold=2.4)
    rows = []
    for s in segments:
        rows.append({'start': s.start, 'end': s.end, 'original': s.text,
                     'avgLogprob': s.avg_logprob, 'noSpeechProbability': s.no_speech_prob,
                     'compressionRatio': s.compression_ratio,
                     'words': [{'start': w.start, 'end': w.end, 'text': w.word} for w in (s.words or [])]})
        progress.value = min(duration, max(0, s.end))
    return normalize({'language': info.language, 'languageProbability': info.language_probability,
                      'segments': rows}, duration, job_id)


def infer_child(model, pcm, language, job_id, duration, progress, result):
    try:
        doc, quality = infer(model, pcm, language, job_id, duration, progress)
        Path(result).write_text(json.dumps({'document': doc, 'quality': quality}, ensure_ascii=False))
    except Exception as error:
        code = str(error) if isinstance(error, TranscriptError) else 'INFERENCE_FAILED'
        Path(result).write_text(json.dumps({'error': code}))


def bounded_infer(model, pcm, language, job_id, duration, progress, lost):
    result = pcm.parent / 'result.json'
    child = multiprocessing.get_context('spawn').Process(target=infer_child,
        args=(model, pcm, language, job_id, duration, progress, str(result)))
    child.start()
    deadline = time.monotonic() + 3 * 3600
    try:
        while child.is_alive():
            if lost.is_set():
                raise TranscriptError('AUDIO_CHANGED')
            if time.monotonic() >= deadline:
                raise TranscriptError('JOB_TIMEOUT')
            child.join(timeout=1)
        if child.exitcode != 0 or not result.exists() or result.stat().st_size > 2 * 1024 * 1024:
            raise TranscriptError('INFERENCE_FAILED')
        value = json.loads(result.read_text())
        if value.get('error'):
            raise TranscriptError(value['error'])
        return value['document'], value['quality']
    finally:
        if child.is_alive():
            child.terminate(); child.join(timeout=5)
            if child.is_alive(): child.kill(); child.join(timeout=5)
        child.close()


def process(job, token):
    started = time.monotonic()
    stopped, lost = threading.Event(), threading.Event()
    progress = multiprocessing.get_context('spawn').Value('d', 0.0)
    def renew():
        while not stopped.wait(20):
            try:
                if not sql_call('heartbeat', (job['id'], token, progress.value)):
                    lost.set()
                    return
            except Exception:
                lost.set()
                return
    threading.Thread(target=renew, daemon=True).start()
    try:
        path = source_file(os.environ['MUWA_ASR_STORAGE'], job['audio_filename'], job['audio_sha256'])
        if shutil.disk_usage(os.environ['MUWA_ASR_STATE']).free < 512 * 1024 * 1024:
            raise TranscriptError('DISK_FULL')
        with tempfile.TemporaryDirectory(prefix='audio-', dir=os.environ['MUWA_ASR_STATE']) as temp:
            pcm = Path(temp) / 'input.wav'
            actual_duration = decode(path, pcm)
            if abs(actual_duration - job['duration']) > max(1, actual_duration * 0.01):
                raise TranscriptError('INVALID_AUDIO')
            document, quality = bounded_infer(os.environ['MUWA_ASR_MODEL'], pcm, job['language'], job['id'],
                                             min(actual_duration, job['duration']), progress, lost)
        if lost.is_set():
            print(json.dumps({'event': 'asr_lease_lost', 'job': str(job['id'])}), flush=True)
            return
        quality['elapsedSeconds'] = round(time.monotonic() - started, 2)
        applied = sql_call('finish', (job['id'], token, Jsonb(document), Jsonb(quality)))
        print(json.dumps({'event': 'asr_finished', 'job': str(job['id']), 'saved': applied,
                          'lines': len(document['segments']), 'needsReview': quality['needsReview'],
                          'elapsedSeconds': quality['elapsedSeconds']}), flush=True)
    except Exception as error:
        code = str(error) if isinstance(error, TranscriptError) else 'INFERENCE_FAILED'
        if code not in {'INVALID_AUDIO', 'NO_SPEECH', 'INVALID_TRANSCRIPT', 'AUDIO_CHANGED', 'JOB_TIMEOUT', 'DISK_FULL'}:
            code = 'INFERENCE_FAILED'
        try:
            sql_call('fail', (job['id'], token, code))
        finally:
            print(json.dumps({'event': 'asr_failed', 'job': str(job['id']), 'code': code}), flush=True)
    finally:
        stopped.set()


def main():
    os.umask(0o027)
    def shutdown(*_):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, shutdown)
    logging.getLogger('faster_whisper').setLevel(logging.ERROR)
    print(json.dumps({'event': 'asr_started', 'model': 'large-v3', 'device': 'cpu', 'paidProvider': False}), flush=True)
    while True:
        try:
            token = uuid.uuid4()
            with connect() as db:
                job = db.execute('SELECT * FROM muwa_claim_asr(%s)', (token,)).fetchone()
            if job:
                process(job, token)
            else:
                time.sleep(5)
        except Exception:
            # No traceback/SQL/credentials/transcript in service logs.
            print(json.dumps({'event': 'asr_queue_unavailable'}), flush=True)
            time.sleep(30)


if __name__ == '__main__':
    main()
