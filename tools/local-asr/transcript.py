"""Validate acoustic output without rewriting religious text or inventing timing."""
import math
import re


class TranscriptError(ValueError):
    pass


def finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def normalize(raw, duration, identifier):
    if not finite(duration) or not 0 < duration <= 3600:
        raise TranscriptError('INVALID_AUDIO')
    language = raw.get('language', '')
    if not isinstance(language, str) or not re.fullmatch(r'[a-z]{2,3}', language):
        raise TranscriptError('INVALID_TRANSCRIPT')
    rows, warnings = [], []
    for item in raw.get('segments', []):
        start, end = item.get('start'), item.get('end')
        text = item.get('original', '').strip()
        if not text:
            continue
        if (not finite(start) or not finite(end) or start < 0 or end <= start
                or end > duration + 0.25 or (rows and start < rows[-1]['end']) or len(text) > 1200):
            raise TranscriptError('INVALID_TRANSCRIPT')
        end = min(end, duration)
        if end <= start:
            raise TranscriptError('INVALID_TRANSCRIPT')
        avg = item.get('avgLogprob', 0)
        silence = item.get('noSpeechProbability', 0)
        compression = item.get('compressionRatio', 0)
        if not all(finite(x) for x in (avg, silence, compression)):
            raise TranscriptError('INVALID_TRANSCRIPT')
        # Preserve refrains; repeated singing is not automatically a hallucination.
        if avg < -1 or silence > 0.6 or compression > 2.4:
            warnings.append('UNCERTAIN_PHRASE')
        words, last = [], start
        for w in item.get('words', []):
            a, b, t = w.get('start'), w.get('end'), w.get('text', '').strip()
            if not finite(a) or not finite(b) or not t or len(t) > 100 or a < last or b <= a or b > end:
                words = []
                break
            words.append({'text': t, 'start': a, 'end': b})
            last = b
        simplify = lambda s: ' '.join(s.split())
        if simplify(' '.join(w['text'] for w in words)) != simplify(text):
            words = []
        rows.append({'id': 's' + str(len(rows)), 'start': start, 'end': end, 'original': text,
                     'words': words, 'timing': 'estimated' if words else 'phrase'})
        if len(rows) > 600:
            raise TranscriptError('INVALID_TRANSCRIPT')
    if not rows:
        raise TranscriptError('NO_SPEECH')
    probability = raw.get('languageProbability', 0)
    if not finite(probability) or not 0 <= probability <= 1:
        raise TranscriptError('INVALID_TRANSCRIPT')
    if probability < 0.8:
        warnings.append('UNCERTAIN_LANGUAGE')
    quality = {'needsReview': bool(warnings), 'languageProbability': probability,
               'model': 'Whisper large-v3 / CPU int8', 'warnings': sorted(set(warnings))}
    return {'version': 2, 'id': str(identifier), 'language': language, 'segments': rows}, quality
