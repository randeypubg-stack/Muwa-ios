import {z} from 'zod';
export const schema=z.object({});
export type CatalogTrack={id:string;title:string;artist:string;duration:number;audio:string;artwork:string|null;language:string;captionsRevision:number};
export type OutputType={version:1;tracks:CatalogTrack[]};
export async function getCatalogTracks(init?:RequestInit):Promise<OutputType>{const r=await fetch('/_api/catalog/tracks',init);if(!r.ok)throw new Error('Каталог недоступен.');return r.json();}
