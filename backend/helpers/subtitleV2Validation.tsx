type Word = { text: string; start: number; end: number };
type Segment = { id: string; start: number; end: number; original: string; words: Word[]; timing: "estimated" | "phrase" };
type Document = { version: 2; id: string; language: string; segments: Segment[] };
const text = (x: unknown, max = 1200) => typeof x === "string" ? x.trim().slice(0, max) : "";
const number = (x: unknown) => typeof x === "number" && Number.isFinite(x) ? x : NaN;
function original(raw: unknown, duration: number, id: string): Document {
  const obj = raw as Record<string, unknown> | null;
  if (!obj || !Array.isArray(obj.segments) || !Number.isFinite(duration) || duration <= 0) throw new Error("INVALID_TRANSCRIPT");
  const language = text(obj.language, 16).toLowerCase();
  if (!/^[a-z]{2,3}(-[a-z]{2,4})?$/.test(language)) throw new Error("INVALID_LANGUAGE");
  const segments: Segment[] = [];
  const rows = obj.segments.filter(x => x && typeof x === "object").sort((a,b) => number(a.start)-number(b.start));
  for (const row of rows) {
    const start = number(row.start), end = number(row.end), value = text(row.original);
    if (!value || start < 0 || !Number.isFinite(start) || !Number.isFinite(end) || end <= start || end > duration+0.25) continue;
    if (segments.length && start < segments[segments.length-1].end) continue;
    const safeEnd = Math.min(end, duration);
    if (safeEnd <= start) continue;
    const words: Word[] = [];
    let validWords = Array.isArray(row.words) && row.words.length > 0;
    if (validWords) for (const w of row.words) {
      if (!w || typeof w !== "object") { validWords=false; break; }
      const a=number(w.start), b=number(w.end), t=text(w.text,100);
      if (!t || !Number.isFinite(a) || !Number.isFinite(b) || a<start || b>safeEnd || b<=a || (words.length && a<words[words.length-1].end)) { validWords=false; break; }
      words.push({text:t,start:a,end:b});
    }
    const normalize=(s:string)=>s.replace(/\s+/g," ").trim();
    if (normalize(words.map(w=>w.text).join(" "))!==normalize(value)) validWords=false;
    segments.push({id:`s${segments.length}`,start,end:safeEnd,original:value,words:validWords?words:[],timing:validWords?"estimated":"phrase"});
    if(segments.length>=600) throw new Error("TRANSCRIPT_TOO_LONG");
  }
  if(!segments.length) throw new Error("NO_SPEECH");
  return {version:2,id,language,segments};
}
function translation(raw: unknown, doc: Document): Record<string,string> {
  const rows=(raw as {segments?:unknown})?.segments;
  if(!Array.isArray(rows)) throw new Error("INVALID_TRANSLATION");
  const result:Record<string,string>={};
  const ids=new Set(doc.segments.map(s=>s.id));
  for(const row of rows) {
    if(!row || typeof row!=="object" || typeof row.id!=="string" || !ids.has(row.id) || Object.hasOwn(result,row.id)) throw new Error("INVALID_TRANSLATION_IDS");
    const value=text(row.text,2000); if(!value) throw new Error("EMPTY_TRANSLATION");
    result[row.id]=value;
  }
  if(Object.keys(result).length!==ids.size) throw new Error("INCOMPLETE_TRANSLATION");
  return result;
}
export const subtitleV2Validation = {original,translation};
