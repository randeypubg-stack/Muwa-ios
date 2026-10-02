import {randomUUID} from 'node:crypto';
import {sql,type Transaction} from 'kysely';
import {upload,getInfo,getUrl,listFolder} from '@floot/storage';
import {db} from './db';
import type {DB,Json} from './schema';
import {getServerUserSession} from './getServerUserSession';
import {NotAuthenticatedError,setServerSession} from './getSetServerSession';
import {adminValidation,type AdminAction,type AdminQuery,type AdminState,type AdminResult,type UploadFile,type Caption} from './adminValidation';
class AdminError extends Error {constructor(message:string,readonly status=400){super(message);}}
function fail(message:string,status=400):never{throw new AdminError(message,status);}
const json=(body:unknown,status=200)=>Response.json(body,{status,headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
const origins=['https://muwa-app.floot.app','https://20d2f317-3710-4331-80ee-ea6072056928.sandbox.floot.app'];
async function audit(tx:Transaction<DB>,actorId:number,action:string,entityId:string,details:Json={}){
 await tx.insertInto('adminAuditEvents').values({actorId,action,entityId,details}).execute();
}
async function track(tx:Transaction<DB>,id:string,revision:number|undefined){
 const row=await tx.selectFrom('catalogTracks').selectAll().where('id','=',id).forUpdate().executeTakeFirst();
 if(!row)fail('Нашид не найден.',404);
 if(row.revision!==revision)fail('Запись изменена в другой сессии. Обновите список и откройте её заново.',409);
 return row;
}
async function submission(tx:Transaction<DB>,id:string,revision:number){
 const row=await tx.selectFrom('publicationDrafts').selectAll().where('id','=',id).forUpdate().executeTakeFirst();
 if(!row)fail('Публикация не найдена.',404);
 if(row.status!=='pending'||row.revision!==revision)fail('Публикация уже обработана или изменена. Обновите список.',409);
 return row;
}
const ext:Record<string,string>={'audio/mpeg':'mp3','audio/mp4':'m4a','audio/x-m4a':'m4a','audio/wav':'wav','image/jpeg':'jpg','image/png':'png','image/webp':'webp'};
async function prepare(userId:number,files:{part:'audio'|'cover';contentType:string;sizeBytes:number;sourceUrl?:string}[],trackId?:string,submissionId?:string):Promise<AdminResult>{
 if(new Set(files.map(f=>f.part)).size!==files.length)fail('Один файл на каждое назначение.');
 const id=randomUUID();
 const prepared:UploadFile[]=[];
 for(const file of files){
  const filename=`catalog/${id}/${file.part}.${ext[file.contentType]}`;
  const result=await upload({visibility:'public',filename,contentType:file.contentType,sizeBytes:file.sizeBytes,ifAbsent:true});
  if(!result.ok)fail('Не удалось подготовить хранилище. Повторите позже.',503);
  prepared.push({...file,filename,url:result.url,presignedUrl:result.presignedUrl,headers:result.headers});
 }
 // Never persist PUT credentials or private GET credentials; they expire and are returned only to this admin.
 const saved=prepared.map(({part,filename,url,contentType,sizeBytes})=>({part,filename,url,contentType,sizeBytes}));
 await db.insertInto('catalogUploads').values({id,userId,trackId:trackId??null,submissionId:submissionId??null,files:saved,expiresAt:new Date(Date.now()+15*60*1000)}).execute();
 return {ok:true,uploadId:id,files:prepared};
}
async function verifiedPlan(id:string,userId:number,trackId?:string,submissionId?:string){
 const row=await db.selectFrom('catalogUploads').selectAll().where('id','=',id).where('userId','=',userId).executeTakeFirst();
 if(!row || row.consumedAt || row.expiresAt<=new Date() || row.trackId!==(trackId??null) || row.submissionId!==(submissionId??null))fail('Загрузка устарела. Подготовьте файлы заново.',409);
 const files=row.files as unknown as UploadFile[];
 for(const file of files){
  const info=await getInfo({visibility:'public',filename:file.filename});
  if(!info.ok || !info.exists || info.sizeBytes!==file.sizeBytes)fail('Файл ещё не загружен полностью. Повторите загрузку.');
 }
 return files;
}
async function consume(tx:Transaction<DB>,id:string,userId:number){
 const result=await tx.updateTable('catalogUploads').set({consumedAt:new Date()}).where('id','=',id).where('userId','=',userId).where('consumedAt','is',null).where('expiresAt','>',new Date()).returning('id').executeTakeFirst();
 if(!result)fail('Эта загрузка уже использована или устарела.',409);
}
async function privateFile(key:string|null,id:string,part:'audio'|'cover'){
 if(!key)return null;
 if(!new RegExp(`^publications/${id}/${part}\\.[a-z0-9]{1,8}$`).test(key))fail('Некорректный путь публикации.');
 const info=await getInfo({visibility:'private',filename:key});
 if(!info.ok || !info.exists || info.sizeBytes<=0 || info.sizeBytes>(part==='audio'?100:10)*1024*1024)fail('Файл публикации недоступен.');
 const source=await getUrl({visibility:'private',filename:key,expiresInSeconds:900});
 if(!source.ok)fail('Файл публикации недоступен.');
 const extension=key.split('.').pop();
 const mime=Object.entries(ext).find(([,v])=>v===extension)?.[0];
 if(!mime || !mime.startsWith(part==='audio'?'audio/':'image/'))fail('Формат публикации не поддерживается.');
 return {part,contentType:mime,sizeBytes:info.sizeBytes,sourceUrl:source.url};
}
async function refresh(userId:number,cursor?:{token?:string;offset:number}){
 // Scan ready markers; never publish presigned drafts or trust client-supplied account IDs.
 const listing=await listFolder({visibility:'private',key:'publications/',continuationToken:cursor?.token});
 if(!listing.ok)fail('Не удалось прочитать публикации.',503);
 let refreshed=0;
 const offset=cursor?.offset??0;
 const folders=listing.folders.slice(offset,offset+25);
 for(const folder of folders){
  const id=folder.replace(/^private\//,'').replace(/\/$/,'').split('/').pop()!;
  if(!/^[0-9a-f-]{36}$/i.test(id))continue;
  const existing=await db.selectFrom('publicationDrafts').select(['status']).where('id','=',id).executeTakeFirst();
  if(existing && existing.status!=='uploading')continue;
  const filename=`publications/${id}/submission.json`;
  const info=await getInfo({visibility:'private',filename});
  if(!info.ok || !info.exists || info.sizeBytes>256*1024)continue;
  const url=await getUrl({visibility:'private',filename});
  if(!url.ok)continue;
  const response=await fetch(url.url,{signal:AbortSignal.timeout(10000)});
  if(!response.ok)continue;
  const data:unknown=await response.json().catch(()=>null);
  if(!data || typeof data!=='object')continue;
  const value=data as Record<string,unknown>;
  if(typeof value.title!=='string'||!value.title.trim()||value.title.length>180||typeof value.artist!=='string'||!value.artist.trim()||value.artist.length>180||typeof value.audioStorageKey!=='string')continue;
  const audioKey=value.audioStorageKey,coverKey=typeof value.coverStorageKey==='string'?value.coverStorageKey:null;
  if(!new RegExp(`^publications/${id}/audio\\.[a-z0-9]{1,8}$`).test(audioKey) || (coverKey&&!new RegExp(`^publications/${id}/cover\\.[a-z0-9]{1,8}$`).test(coverKey)))continue;
  const audioInfo=await getInfo({visibility:'private',filename:audioKey});
  if(!audioInfo.ok || !audioInfo.exists || audioInfo.sizeBytes<=0)continue;
  await db.transaction().execute(async tx=>{
   const result=await tx.insertInto('publicationDrafts').values({id,status:'pending',title:value.title as string,artist:value.artist as string,language:typeof value.language==='string'?value.language.slice(0,10):'ar',audioKey,coverKey}).onConflict(oc=>oc.column('id').doUpdateSet({status:'pending',title:value.title as string,artist:value.artist as string,language:typeof value.language==='string'?value.language.slice(0,10):'ar',audioKey,coverKey,updatedAt:new Date(),revision:sql`publication_drafts.revision+1`}).where('publicationDrafts.status','=','uploading')).returning('id').executeTakeFirst();
   if(result){await audit(tx,userId,'submission.received',id);refreshed++;}
  });
 }
 const nextCursor=offset+25<listing.folders.length?{token:cursor?.token,offset:offset+25}:listing.nextContinuationToken?{token:listing.nextContinuationToken,offset:0}:undefined;
 return {ok:true as const,refreshed,nextCursor};
}
async function execute(input:AdminAction,userId:number):Promise<AdminResult>{
 if(input.action==='refresh-submissions')return refresh(userId,input.cursor);
 if(input.action==='prepare-upload'){
  if(input.trackId)await db.transaction().execute(tx=>track(tx,input.trackId!,input.revision));
  return prepare(userId,input.files,input.trackId);
 }
 if(input.action==='open-submission'||input.action==='prepare-approval'){
  const row=await db.selectFrom('publicationDrafts').selectAll().where('id','=',input.submissionId).executeTakeFirst();
  if(!row)fail('Публикация не найдена.',404);
  const audio=await privateFile(row.audioKey,row.id,'audio');
  const cover=await privateFile(row.coverKey,row.id,'cover');
  if(!audio)fail('Аудио отсутствует.');
  if(input.action==='open-submission')return {ok:true,audioUrl:audio.sourceUrl,artworkUrl:cover?.sourceUrl};
  if(row.status!=='pending'||row.revision!==input.revision)fail('Публикация уже обработана или изменена.',409);
  return prepare(userId,[audio,...(cover?[cover]:[])],undefined,row.id);
 }
 if(input.action==='save-track'){
  const files=input.uploadId?await verifiedPlan(input.uploadId,userId,input.trackId):[];
  return db.transaction().execute(async tx=>{
   const current=input.trackId?await track(tx,input.trackId,input.revision):null;
   const audio=files.find(f=>f.part==='audio'),cover=files.find(f=>f.part==='cover');
   if(!current&&!audio)fail('Сначала загрузите аудио.');
   const id=current?.id??`muwa-${randomUUID()}`;
   const values={title:input.title,artist:input.artist,language:input.language,duration:input.duration,status:input.status,audioUrl:audio?.url??current?.audioUrl??null,audioFilename:audio?.filename??current?.audioFilename??null,artworkUrl:cover?.url??current?.artworkUrl??null,coverFilename:cover?.filename??current?.coverFilename??null,updatedAt:new Date()};
   if(input.status==='published'&&!values.audioUrl)fail('Нельзя публиковать без аудио.');
   if(input.uploadId)await consume(tx,input.uploadId,userId);
   // Replacing audio invalidates old timings; never silently attach old captions to new audio.
   const captionsChanged=!!audio&&!!current;
   if(current)await tx.updateTable('catalogTracks').set({...values,revision:current.revision+1,...(captionsChanged?{captions:[],captionsRevision:current.captionsRevision+1}:{})}).where('id','=',id).execute();
   else await tx.insertInto('catalogTracks').values({...values,id,createdBy:userId}).execute();
   await audit(tx,userId,current?'track.updated':'track.created',id,{title:input.title,status:input.status,audioReplaced:!!audio});
   return {ok:true,trackId:id};
  });
 }
 if(input.action==='set-status'||input.action==='save-captions')return db.transaction().execute(async tx=>{
  const row=await track(tx,input.trackId,input.revision);
  if(input.action==='set-status'){
   if(input.status==='published'&&(!row.audioUrl||row.duration<=0||!row.title.trim()))fail('Заполните название и загрузите аудио.');
   await tx.updateTable('catalogTracks').set({status:input.status,revision:row.revision+1,updatedAt:new Date()}).where('id','=',row.id).execute();
   await audit(tx,userId,'track.'+input.status,row.id);
  }else{
   if(input.captions.some(c=>c.end>row.duration+0.1))fail('Субтитры выходят за длительность аудио.');
   await tx.updateTable('catalogTracks').set({captions:input.captions,captionsRevision:row.captionsRevision+1,revision:row.revision+1,updatedAt:new Date()}).where('id','=',row.id).execute();
   await audit(tx,userId,'captions.updated',row.id,{lines:input.captions.length});
  }
  return {ok:true};
 });
 if(input.action==='reject-submission')return db.transaction().execute(async tx=>{
  const row=await submission(tx,input.submissionId,input.revision);
  await tx.updateTable('publicationDrafts').set({status:'rejected',rejectionReason:input.reason,revision:row.revision+1,updatedAt:new Date()}).where('id','=',row.id).execute();
  await audit(tx,userId,'submission.rejected',row.id,{reason:input.reason});
  return {ok:true};
 });
 if(input.action==='approve-submission'){
  const files=await verifiedPlan(input.uploadId,userId,undefined,input.submissionId);
  const audio=files.find(f=>f.part==='audio'),cover=files.find(f=>f.part==='cover');
  if(!audio)fail('Аудио не загружено.');
  return db.transaction().execute(async tx=>{
   const row=await submission(tx,input.submissionId,input.revision);
   await consume(tx,input.uploadId,userId);
   const id=`muwa-${row.id}`;
   await tx.insertInto('catalogTracks').values({id,title:input.title,artist:input.artist,language:input.language,duration:input.duration,status:'published',audioUrl:audio.url,audioFilename:audio.filename,artworkUrl:cover?.url??null,coverFilename:cover?.filename??null,sourceSubmissionId:row.id,createdBy:userId}).execute();
   await tx.updateTable('publicationDrafts').set({status:'published',trackId:id,revision:row.revision+1,updatedAt:new Date()}).where('id','=',row.id).execute();
   await audit(tx,userId,'submission.published',row.id,{trackId:id});
   return {ok:true,trackId:id};
  });
 }
 fail('Неизвестное действие.');
}
async function state(input:AdminQuery):Promise<AdminState>{
 const count=await db.selectFrom('catalogTracks').select(['status',sql<number>`count(*)::integer`.as('count')]).groupBy('status').execute();
 const pending=await db.selectFrom('publicationDrafts').select(sql<number>`count(*)::integer`.as('count')).where('status','=','pending').executeTakeFirstOrThrow();
 const base:AdminState={tracks:[],submissions:[],events:[],total:0,page:input.page,stats:{published:count.find(r=>r.status==='published')?.count??0,drafts:count.find(r=>r.status==='draft')?.count??0,pending:pending.count},recognition:{enabled:false,message:'Автораспознавание приостановлено. Редактирование и импорт готовых субтитров доступны.'}};
 const offset=(input.page-1)*20;
 if(input.section==='catalog'){
  let query=db.selectFrom('catalogTracks');
  if(input.status!=='all')query=query.where('status','=',input.status);
  if(input.search)query=query.where(eb=>eb.or([eb('title','ilike','%'+input.search+'%'),eb('artist','ilike','%'+input.search+'%')]));
  base.total=Number((await query.select(sql<number>`count(*)::integer`.as('count')).executeTakeFirstOrThrow()).count);
  const rows=await query.select(['id','title','artist','language','duration','audioUrl','artworkUrl','status','revision','captionsRevision','captions','updatedAt']).orderBy('createdAt','desc').orderBy('id').offset(offset).limit(20).execute();
  base.tracks=rows.map(r=>({...r,captions:r.captions as unknown as Caption[],updatedAt:r.updatedAt.toISOString()}));
 }else if(input.section==='submissions'){
  let query=db.selectFrom('publicationDrafts');
  if(input.status!=='all')query=query.where('status','=',input.status);
  if(input.search)query=query.where(eb=>eb.or([eb('title','ilike','%'+input.search+'%'),eb('artist','ilike','%'+input.search+'%')]));
  base.total=Number((await query.select(sql<number>`count(*)::integer`.as('count')).executeTakeFirstOrThrow()).count);
  const rows=await query.select(['id','title','artist','language','status','revision','userId','rejectionReason','updatedAt']).orderBy('updatedAt','desc').orderBy('id').offset(offset).limit(20).execute();
  base.submissions=rows.map(r=>({...r,updatedAt:r.updatedAt.toISOString()}));
 }else{
  base.total=Number((await db.selectFrom('adminAuditEvents').select(sql<number>`count(*)::integer`.as('count')).executeTakeFirstOrThrow()).count);
  const rows=await db.selectFrom('adminAuditEvents').leftJoin('users','users.id','adminAuditEvents.actorId').select(['adminAuditEvents.id','action','entityId','users.displayName as actor','adminAuditEvents.createdAt']).orderBy('adminAuditEvents.id','desc').offset(offset).limit(20).execute();
  base.events=rows.map(r=>({...r,id:String(r.id),createdAt:r.createdAt.toISOString()}));
 }
 return base;
}
async function handle(request:Request,method:'GET'|'POST'){
 try{
  if(method==='POST'){
   if(!request.headers.get('content-type')?.includes('application/json'))fail('Нужен JSON-запрос.',415);
   const origin=request.headers.get('origin');
   if(origin&&!origins.includes(origin))fail('Недопустимый источник запроса.',403);
   if(request.headers.get('sec-fetch-site')==='cross-site')fail('Недопустимый источник запроса.',403);
  }
  const {user,session}=await getServerUserSession(request);
  if(user.role!=='admin')fail('Доступ только администраторам Muwa.',403);
  let output:AdminResult|AdminState;
  if(method==='POST'){
   const body=await request.text();
   if(body.length>2*1024*1024)fail('Запрос слишком большой.',413);
   const parsed=adminValidation.action.safeParse(JSON.parse(body));
   if(!parsed.success)fail(parsed.error.issues[0]?.message??'Проверьте данные.');
   output=await execute(parsed.data,user.id);
  }else{
   const parsed=adminValidation.query.safeParse(Object.fromEntries(new URL(request.url).searchParams));
   if(!parsed.success)fail('Проверьте фильтры.');
   output=await state(parsed.data);
  }
  const response=json(output);
  await setServerSession(response,{...session,lastAccessed:session.lastAccessed.getTime()});
  return response;
 }catch(error){
  if(error instanceof NotAuthenticatedError)return json({error:'Войдите в аккаунт Muwa.'},401);
  if(error instanceof AdminError)return json({error:error.message},error.status);
  if(error instanceof SyntaxError)return json({error:'Некорректный JSON.'},400);
  console.error('Muwa admin request failed',error instanceof Error?error.name:'unknown');
  return json({error:'Сервис временно недоступен. Повторите позже.'},503);
 }
}
export const adminService={handle};
