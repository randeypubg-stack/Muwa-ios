import { normalizeWhisper, subtitleOpenAI, SubtitleProviderError } from './subtitleOpenAI';
import { subtitleV2Validation } from './subtitleV2Validation';

describe('OpenAI subtitle provider', () => {
  it('maps detected language and preserves timed original words', () => {
    const raw=normalizeWhisper({language:'arabic',segments:[{start:1,end:3,text:'مرحبا بكم'}],words:[{word:'مرحبا',start:1,end:2},{word:'بكم',start:2,end:3}]});
    const doc=subtitleV2Validation.original(raw,10,'test');
    expect(doc.language).toBe('ar');
    expect(doc.segments[0].words.length).toBe(2);
    expect(doc.segments[0].start).toBe(1);
  });
  it('uses phrase timing if the provider word text is incomplete', () => {
    const raw=normalizeWhisper({language:'english',segments:[{start:0,end:3,text:'Hello everyone'}],words:[{word:'Hello',start:0,end:1}]});
    expect(subtitleV2Validation.original(raw,10,'test').segments[0].words).toEqual([]);
  });
  it('omits low-confidence silence without inventing phrases', () => {
    const raw=normalizeWhisper({language:'english',segments:[{start:0,end:3,text:'phantom',no_speech_prob:0.9,avg_logprob:-2}]});
    expect(() => subtitleV2Validation.original(raw,10,'test')).toThrowError('NO_SPEECH');
  });
  it('rejects arbitrary audio hosts before fetching', async () => {
    const fetcher=spyOn(globalThis,'fetch');
    await expectAsync(subtitleOpenAI.original('https://example.com/audio.mp3')).toBeRejected();
    expect(fetcher).not.toHaveBeenCalled();
  });
  it('reports exhausted credits distinctly from request rate limits', async () => {
    const previous=process.env.OPENAI_API_KEY;
    process.env.OPENAI_API_KEY='test-only';
    try {
      spyOn(globalThis,'fetch').and.resolveTo(new Response(JSON.stringify({error:{code:'credit_balance_exhausted',type:'insufficient_quota'}}),{status:429}));
      try { await subtitleOpenAI.translate('sample','Return JSON'); fail('Expected provider error'); }
      catch(e) { expect(e instanceof SubtitleProviderError).toBeTrue(); expect((e as SubtitleProviderError).code).toBe('OUT_OF_CREDITS'); expect((e as SubtitleProviderError).status).toBe(503); }
    } finally { if(previous===undefined)Reflect.deleteProperty(process.env, 'OPENAI_API_KEY');else process.env.OPENAI_API_KEY=previous; }
  });
});


