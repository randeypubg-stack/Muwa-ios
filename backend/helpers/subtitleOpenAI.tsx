// Server-only provider. Never expose credentials or upstream error bodies.
export class SubtitleProviderError extends Error {
  constructor(public code: string, public status: number) { super(code); }
}
const MAX_AUDIO = 24 * 1024 * 1024;
async function api(path: string, body: BodyInit, jsonBody = false) {
  const key = process.env.OPENAI_API_KEY;
  if (!key) throw new SubtitleProviderError('AI_NOT_CONFIGURED', 503);
  const response = await fetch('https://api.openai.com/v1/' + path, {
    method: 'POST', headers: { Authorization: `Bearer ${key}`, ...(jsonBody ? {'Content-Type':'application/json'} : {}) },
    body, signal: AbortSignal.timeout(180000), redirect: 'error'
  });
  if (!response.ok) {
    const detail = await response.json().catch(() => null);
    const quota = detail?.error?.type === 'insufficient_quota' || ['insufficient_quota','credit_balance_exhausted'].includes(detail?.error?.code);
    throw new SubtitleProviderError(quota ? 'OUT_OF_CREDITS' : response.status === 429 ? 'RATE_LIMIT' : 'AI_UNAVAILABLE', response.status === 429 && !quota ? 429 : 503);
  }
  return response.json();
}
export function normalizeWhisper(raw: any) {
  const languageName = String(raw?.language ?? '').toLowerCase();
  const names = new Intl.DisplayNames(['en'], {type: 'language'});
  let language = languageName;
  if (!/^[a-z]{2,3}$/.test(language)) {
    language = '';
    for (let a=97; a<=122 && !language; a++) for (let b=97; b<=122; b++) {
      const code = String.fromCharCode(a,b);
      if (names.of(code)?.toLowerCase() === languageName) { language=code; break; }
    }
  }
  const words = Array.isArray(raw?.words) ? raw.words : [];
  const segments = (Array.isArray(raw?.segments) ? raw.segments : [])
    .filter((s:any) => !(s.no_speech_prob > 0.6 && s.avg_logprob < -1))
    .map((s:any) => ({start:s.start,end:s.end,original:s.text,
      words:words.filter((w:any)=>w.start>=s.start && w.end<=s.end).map((w:any)=>({text:w.word,start:w.start,end:w.end}))}));
  return {language,segments};
}
async function original(src: string) {
  if (!/^\/_cdn\/static\/[A-Za-z0-9_-]+\.(mp3|m4a|wav|aac|ogg)$/.test(src)) throw new Error('INVALID_SOURCE');
  const response = await fetch(new URL(src,'https://muwa-app.floot.app'), {redirect:'error',signal:AbortSignal.timeout(30000)});
  if (!response.ok || !response.body) throw new Error('AUDIO_UNAVAILABLE');
  if (Number(response.headers.get('content-length')) > MAX_AUDIO) { await response.body.cancel(); throw new Error('AUDIO_TOO_LARGE'); }
  const reader=response.body.getReader(); const chunks: Uint8Array[]=[]; let size=0;
  try {
    while(true) { const item=await reader.read(); if(item.done)break; size+=item.value.byteLength;
      if(size>MAX_AUDIO) { await reader.cancel(); throw new Error('AUDIO_TOO_LARGE'); } chunks.push(item.value); }
  } finally { reader.releaseLock(); }
  const bytes=new Uint8Array(size); let offset=0;
  for(const chunk of chunks) { bytes.set(chunk,offset); offset+=chunk.byteLength; }
  const form=new FormData();
  form.append('file',new Blob([bytes]),src.split('/').pop()!);
  form.append('model','whisper-1'); form.append('response_format','verbose_json');
  form.append('timestamp_granularities[]','word'); form.append('timestamp_granularities[]','segment');
  return normalizeWhisper(await api('audio/transcriptions',form));
}
async function translate(content: string, instruction: string) {
  const result=await api('chat/completions',JSON.stringify({model:'gpt-4.1-mini',temperature:0,
    response_format:{type:'json_object'},messages:[{role:'system',content:instruction},{role:'user',content}],max_completion_tokens:16000}),true);
  const choice=result.choices?.[0];
  if(choice?.finish_reason!=='stop' || !choice.message?.content)throw new Error('INCOMPLETE_TRANSLATION');
  return JSON.parse(choice.message.content);
}
export const subtitleOpenAI={original,translate};

