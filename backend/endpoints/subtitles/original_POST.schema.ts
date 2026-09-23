import { z } from "zod";
export const schema=z.object({
  src:z.string().max(500).regex(/^\/_cdn\/static\/[A-Za-z0-9_-]+\.(mp3|m4a|wav|aac|ogg)$/i),
  durationSeconds:z.number().positive().max(600),
});
export type InputType=z.infer<typeof schema>;
export type SubtitleDocument={version:2;id:string;language:string;segments:{id:string;start:number;end:number;original:string;words:{text:string;start:number;end:number}[];timing:"estimated"|"phrase"}[]};
export type OutputType=SubtitleDocument;
export async function postSubtitlesOriginal(body:InputType,init?:RequestInit):Promise<OutputType>{
 const r=await fetch('/_api/subtitles/original',{...init,method:'POST',headers:{...init?.headers,'Content-Type':'application/json'},body:JSON.stringify(schema.parse(body))});
 const data=await r.json();if(!r.ok)throw new Error(data.error??'Не удалось распознать');return data;
}
