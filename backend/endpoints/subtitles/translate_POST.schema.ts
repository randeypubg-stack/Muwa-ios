import { z } from "zod";
export const schema=z.object({documentId:z.string().regex(/^[a-f0-9]{64}$/),language:z.enum(['ru','en','tr','uz','kk','fr','ar'])});
export type InputType=z.infer<typeof schema>;
export type OutputType={documentId:string;language:string;segments:Record<string,string>};
export async function postSubtitlesTranslate(body:InputType,init?:RequestInit):Promise<OutputType>{
 const r=await fetch('/_api/subtitles/translate',{...init,method:'POST',headers:{...init?.headers,'Content-Type':'application/json'},body:JSON.stringify(schema.parse(body))});
 const data=await r.json();if(!r.ok)throw new Error(data.error??'Не удалось перевести');return data;
}
