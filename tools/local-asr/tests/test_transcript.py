import hashlib
import math
from pathlib import Path
import tempfile
import unittest
from transcript import normalize, TranscriptError
from worker import source_file, decode

def raw(text='مرحبا بكم'):
    return {'language':'ar','languageProbability':0.99,'segments':[{
        'start':1,'end':3,'original':text,'words':[{'start':1,'end':2,'text':'مرحبا'}, {'start':2,'end':3,'text':'بكم'}]}]}

class TranscriptChecks(unittest.TestCase):
    def test_original_and_acoustic_words_are_preserved(self):
        doc,q=normalize(raw(),10,'job')
        self.assertEqual(doc['segments'][0]['original'],'مرحبا بكم')
        self.assertEqual(len(doc['segments'][0]['words']),2)
        self.assertFalse(q['needsReview'])
    def test_invalid_word_timing_does_not_invent_replacements(self):
        value=raw();value['segments'][0]['words'][1]['start']=1.5
        doc,q=normalize(value,10,'job')
        self.assertEqual(doc['segments'][0]['words'],[])
        self.assertEqual(doc['segments'][0]['timing'],'phrase')
    def test_partial_words_do_not_claim_word_highlighting(self):
        value=raw();value['segments'][0]['words'].pop()
        self.assertEqual(normalize(value,10,'job')[0]['segments'][0]['words'],[])
    def test_uncertain_text_is_saved_verbatim_for_review(self):
        value=raw();value['segments'][0]['avgLogprob']=-1.3;value['languageProbability']=0.7
        doc,q=normalize(value,10,'job')
        self.assertEqual(doc['segments'][0]['original'],'مرحبا بكم')
        self.assertTrue(q['needsReview']);self.assertIn('UNCERTAIN_LANGUAGE',q['warnings'])
    def test_nasheed_refrains_are_not_removed_as_duplicates(self):
        value=raw();value['segments'].append({**value['segments'][0],'start':5,'end':7,'words':[]})
        self.assertEqual(len(normalize(value,10,'job')[0]['segments']),2)
    def test_nan_overlap_out_of_bounds_and_negative_ranges_are_rejected(self):
        for start,end in [(math.nan,3),(-1,3),(1,1),(1,11),(True,3)]:
            value=raw();value['segments'][0].update(start=start,end=end)
            with self.assertRaises(TranscriptError):normalize(value,10,'job')
        value=raw();value['segments'].append({**value['segments'][0],'start':2,'end':4})
        with self.assertRaises(TranscriptError):normalize(value,10,'job')
    def test_no_speech_has_no_fake_subtitle(self):
        with self.assertRaisesRegex(TranscriptError,'NO_SPEECH'):
            normalize({'language':'ar','languageProbability':1,'segments':[]},10,'job')
    def test_phrase_limit(self):
        value=raw();value['segments']=[{'start':i,'end':i+0.5,'original':'كلمة','words':[]} for i in range(601)]
        with self.assertRaises(TranscriptError):normalize(value,1000,'job')
    def test_audio_path_hash_symlink_and_traversal_guards(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);name='catalog/12345678-1234-1234-1234-123456789abc/audio.mp3'
            p=root/name;p.parent.mkdir(parents=True);p.write_bytes(b'original-audio')
            digest=hashlib.sha256(p.read_bytes()).hexdigest()
            self.assertEqual(source_file(root,name,digest),p)
            for bad in ['../audio.mp3','https://host/audio.mp3',name+'?token=x']:
                with self.assertRaises(TranscriptError):source_file(root,bad,digest)
            with self.assertRaisesRegex(TranscriptError,'AUDIO_CHANGED'):source_file(root,name,'a'*64)
            p.unlink();p.symlink_to(root/'outside')
            with self.assertRaises(TranscriptError):source_file(root,name,digest)
    def test_decoder_rejects_playlist_network_fetch(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);p=root/'fake.mp3';p.write_text('#EXTM3U\nhttps://example.invalid/private.mp3\n')
            with self.assertRaisesRegex(TranscriptError,'INVALID_AUDIO'):decode(p,root/'decoded.wav')

if __name__=='__main__':unittest.main()
