import {db} from '../../helpers/db';
import type {OutputType} from './tracks_GET.schema';
export async function handle(){
 try{
  const rows=await db.selectFrom('catalogTracks').select(['id','title','artist','duration','audioUrl','artworkUrl','language','captionsRevision']).where('status','=','published').orderBy('createdAt').orderBy('id').limit(10000).execute();
  const output:OutputType={version:1,tracks:rows.map(r=>({id:r.id,title:r.title,artist:r.artist,duration:r.duration,audio:r.audioUrl!,artwork:r.artworkUrl,language:r.language,captionsRevision:r.captionsRevision}))};
  return Response.json(output,{headers:{'Cache-Control':'public, max-age=30','X-Content-Type-Options':'nosniff'}});
 }catch{return Response.json({error:'Каталог временно недоступен.'},{status:503,headers:{'Cache-Control':'no-store'}});}
}
