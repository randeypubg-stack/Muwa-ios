import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { randomBytes, createHash, randomUUID } from 'node:crypto';
import postgres from 'postgres';
import { serve } from '@hono/node-server';
import superjson from 'superjson';

const connection=process.env.MUWA_TEST_DATABASE_URL;
if(!connection)throw new Error('A disposable audit database is required');
const target=new URL(connection);
if(!['127.0.0.1','localhost'].includes(target.hostname)||target.pathname!=='/muwa_audit')throw new Error('Refusing to reset a non-audit database');
const root=await fs.mkdtemp(path.join(process.env.MUWA_AUDIT_STORAGE_BASE??os.tmpdir(),'muwa-runtime-'));
Object.assign(process.env,{MUWA_DATABASE_URL:connection,MUWA_PUBLIC_ORIGIN:'http://127.0.0.1:1',MUWA_RUNTIME_TEST:'1',MUWA_STORAGE_ROOT:root,MUWA_STORAGE_SECRET:randomBytes(48).toString('hex'),JWT_SECRET:randomBytes(48).toString('hex'),MUWA_BETA_USER_IDS:'1',MUWA_TELEGRAM_OWNER_ID:'1'});
const sql=postgres(connection,{max:1,prepare:false,onnotice:()=>{}});
let checks=0;
const {createApp}=await import('../runtime/app');
const {db}=await import('../helpers/db');
const storage=await import('../helpers/storage');
const server=serve({fetch:createApp().fetch,hostname:'127.0.0.1',port:0});
await new Promise<void>(resolve=>server.listening?resolve():server.once('listening',resolve));
const address=server.address();assert(address&&typeof address!=='string');
const origin='http://127.0.0.1:'+address.port;process.env.MUWA_PUBLIC_ORIGIN=origin;
let cookie='';
async function request(endpoint:string,body?:unknown,options:{cookie?:string;origin?:string;superjson?:boolean}={}) {
 return fetch(origin+'/_api/'+endpoint,{method:body===undefined?'GET':'POST',headers:{...(body===undefined?{}:{'Content-Type':'application/json'}),...(options.cookie??cookie?{Cookie:options.cookie??cookie}:{}),...(options.origin?{Origin:options.origin}:{})},body:body===undefined?undefined:options.superjson?superjson.stringify(body):JSON.stringify(body)});
}
async function status(endpoint:string,body:unknown,expected:number,options={}){const r=await request(endpoint,body,options);assert.equal(r.status,expected,endpoint);await r.arrayBuffer();checks++;}
try {
 await sql.unsafe('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
 const migrations=['base-schema.sql','admin-migration.sql','security-migration.sql','premium-migration.sql','migration.sql','telegram-import-migration.sql','asr-migration.sql'];
 for(const name of migrations)await sql.unsafe(await fs.readFile(name,'utf8'));
 assert.equal((await fetch(origin+'/_health')).status,200);checks++;
 await status('catalog/tracks',undefined,200);
 const catalogHead=await fetch(origin+'/_api/catalog/tracks',{method:'HEAD'});assert.equal(catalogHead.status,200);assert.equal((await catalogHead.arrayBuffer()).byteLength,0);checks++;
 await status('admin/state',undefined,401);
 await status('auth/register_with_password',{},403);
 const token=randomBytes(32).toString('hex'),password=randomBytes(20).toString('hex');
 await sql`insert into owner_setup(id,token_hash,email,expires_at) values(true,${createHash('sha256').update(token).digest('hex')},'owner@muwa.invalid',now()+interval '1 hour')`;
 await status('auth/owner_setup',{token:'0'.repeat(64),password},403);
 await status('auth/owner_setup',{token,password},403,{origin:'https://other.invalid'});
 const setup=await request('auth/owner_setup',{token,password});assert.equal(setup.status,200);
 const header=setup.headers.get('set-cookie')!;assert(header.includes('HttpOnly')&&header.includes('Secure')&&header.includes('SameSite=Lax'));
 cookie=header.split(';')[0];const account=await setup.json();assert.equal(account.user.role,'admin');assert.equal(account.user.id,1);checks++;
 await status('auth/owner_setup',{token,password},403);
 const login=await request('auth/login_with_password',{email:'owner@muwa.invalid',password},{cookie:'',superjson:true});assert.equal(login.status,200);await login.arrayBuffer();checks++;
 await status('auth/login_with_password',{email:'owner@muwa.invalid',password:'incorrect-password' },401,{cookie:'',superjson:true});
 // Prove bcrypt's 72-byte alias cannot become a valid login credential.
 const {hash}=await import('bcryptjs');
 const boundary='p'.repeat(72);
 await sql`update user_passwords set password_hash=${await hash(boundary,10)} where user_id=1`;
 await status('auth/login_with_password',{email:'owner@muwa.invalid',password:boundary+'suffix'},400,{cookie:'',superjson:true});
 await status('auth/login_with_password',{email:'owner@muwa.invalid',password:'я'.repeat(37)},400,{cookie:'',superjson:true});
 await status('auth/login_with_password',{email:'owner@muwa.invalid',password:boundary},200,{cookie:'',superjson:true});
 await sql`update user_passwords set password_hash=${await hash(password,10)} where user_id=1`;

 const empty=await request('catalog/tracks');assert.deepEqual((await empty.json()).tracks,[]);assert.match(empty.headers.get('cache-control')!,/public/);checks++;
 const importSource={channelId:'-1000000012345',messageId:1};
 await status('admin/action',{action:'lookup-telegram-import',source:importSource},200);
 delete process.env.MUWA_TELEGRAM_OWNER_ID;
 await status('admin/action',{action:'lookup-telegram-import',source:importSource},403);
 process.env.MUWA_TELEGRAM_OWNER_ID='1';
 // A valid one-second PCM WAV tests real container bytes, not a fake media URL.
 const audio=Buffer.alloc(16044);audio.write('RIFF',0);audio.writeUInt32LE(audio.length-8,4);audio.write('WAVEfmt ',8);audio.writeUInt32LE(16,16);audio.writeUInt16LE(1,20);audio.writeUInt16LE(1,22);audio.writeUInt32LE(8000,24);audio.writeUInt32LE(16000,28);audio.writeUInt16LE(2,32);audio.writeUInt16LE(16,34);audio.write('data',36);audio.writeUInt32LE(16000,40);
 const prep=await request('admin/action',{action:'prepare-upload',files:[{part:'audio',contentType:'audio/wav',sizeBytes:audio.length}]});assert.equal(prep.status,200);const plan=await prep.json();assert.equal(plan.files.length,1);
 const file=plan.files[0];assert.equal((await fetch(file.presignedUrl,{method:'PUT',headers:file.headers,body:audio})).status,201);checks++;
 assert.equal((await fetch(file.presignedUrl,{method:'PUT',headers:file.headers,body:audio})).status,409);checks++;
 const saved=await request('admin/action',{action:'save-track',uploadId:plan.uploadId,title:'Проверка Muwa',artist:'Muwa',language:'ar',duration:1,status:'draft'});assert.equal(saved.status,200);const id=(await saved.json()).trackId;checks++;
 const pending=await request('catalog/tracks',undefined,{cookie:''});assert.equal((await pending.json()).tracks.length,0);checks++;
 const draftRows=await sql`select audio_url from catalog_tracks where id=${id}`;
 const draftMedia=await fetch(draftRows[0].audio_url,{redirect:'manual'});assert.equal(draftMedia.status,404);await draftMedia.arrayBuffer();checks++;
 const draftHead=await fetch(draftRows[0].audio_url,{method:'HEAD',redirect:'manual'});assert.equal(draftHead.status,404);checks++;
 await status('catalog/captions?trackId='+id,undefined,404,{cookie:''});
 await status('admin/action',{action:'set-status',trackId:id,revision:1,status:'published'},200);
 const catalog=await request('catalog/tracks');const tracks=(await catalog.json()).tracks;assert.equal(tracks.length,1);assert.equal(tracks[0].id,id);assert(tracks[0].audio.startsWith(origin+'/_api/catalog/media'));checks++;
 const emptyCaptionsResponse=await request('catalog/captions?trackId='+id,undefined,{cookie:''});
 const emptyCaptions=await emptyCaptionsResponse.json();assert.equal(emptyCaptions.availability,'unavailable');assert.deepEqual(emptyCaptions.segments,[]);checks++;
 process.env.MUWA_LOCAL_ASR_ENABLED='1';
 const fixtureHash='a'.repeat(64);
 await sql`update catalog_audio_fingerprints set sha256=${fixtureHash} where track_id=${id}`;
 await sql`select muwa_enqueue_asr(${id})`;
 const pendingCaptions=await request('catalog/captions?trackId='+id,undefined,{cookie:''});assert.equal((await pendingCaptions.json()).availability,'processing');checks++;
 await sql`update catalog_asr_jobs set status='ready',quality='{"needsReview":true}',document='{"privateFixture":"must never be public"}' where track_id=${id}`;
 const reviewCaptions=await request('catalog/captions?trackId='+id,undefined,{cookie:''});const reviewPayload=await reviewCaptions.json();
 assert.equal(reviewPayload.availability,'review');assert.deepEqual(reviewPayload.segments,[]);
 assert.deepEqual(Object.keys(reviewPayload).sort(),['availability','revision','segments','source']);checks++;
 await sql`update catalog_asr_jobs set audio_sha256=${'b'.repeat(64)} where track_id=${id}`;
 const staleCaptions=await request('catalog/captions?trackId='+id,undefined,{cookie:''});assert.equal((await staleCaptions.json()).availability,'unavailable');checks++;
 delete process.env.MUWA_LOCAL_ASR_ENABLED;
 const guest=await fetch(tracks[0].audio,{headers:{Range:'bytes=0-43'}});assert.equal(guest.status,206);assert.deepEqual(Buffer.from(await guest.arrayBuffer()),audio.subarray(0,44));checks++;
 const guestHead=await fetch(tracks[0].audio,{method:'HEAD'});assert.equal(guestHead.status,200);assert.equal(guestHead.headers.get('content-length'),String(audio.length));assert.equal((await guestHead.arrayBuffer()).byteLength,0);checks++;
 const publicCatalog=await request('catalog/tracks',undefined,{cookie:''});assert.equal((await publicCatalog.json()).tracks[0].id,id);checks++;
 await status('catalog/tracks',{},401,{cookie:''});
 await status('premium/access',{action:'status'},401,{cookie:''});
 await status('publicationUpload',{},401,{cookie:''});
 await status('admin/action',{action:'set-status',trackId:id,revision:2,status:'draft'},401,{cookie:''});
 const media=await fetch(tracks[0].audio,{headers:{Cookie:cookie,Range:'bytes=0-43'}});assert.equal(media.status,206);assert.equal(media.headers.get('content-range'),'bytes 0-43/16044');assert.deepEqual(Buffer.from(await media.arrayBuffer()),audio.subarray(0,44));checks++;
 const ticket=await storage.getUrl({visibility:'private',filename:file.filename,expiresInSeconds:60});assert(ticket.ok);
 const tampered=ticket.url.slice(0,-1)+(ticket.url.endsWith('0')?'1':'0');assert.equal((await fetch(tampered)).status,403);checks++;
 const head=await fetch(ticket.url,{method:'HEAD'});assert.equal(head.status,200);assert.equal(head.headers.get('content-length'),String(audio.length));checks++;
 const range=await fetch(ticket.url,{headers:{Range:'bytes=999999-'}});assert.equal(range.status,416);checks++;
 const traversal=await storage.upload({visibility:'private',filename:'../outside.wav',contentType:'audio/wav',sizeBytes:1});assert(!traversal.ok);checks++;
 await status('admin/action',{action:'save-captions',trackId:id,revision:2,captions:[{start:0,end:1,ar:'تجربة',ru:'Проверка',en:'Test'}]},200);
 const captions=await request('catalog/captions?trackId='+id,undefined,{cookie:''});assert.equal(captions.status,200);const publishedCaptionPayload=await captions.json();assert.equal(publishedCaptionPayload.segments.length,1);assert.equal(publishedCaptionPayload.availability,'available');checks++;
 await status('diagnostics/events',{platform:'iOS',version:'1.4.0',build:'43',events:[{id:randomUUID(),occurredAt:new Date().toISOString(),area:'playback',errorType:'network',errorCode:-1009}]},200);
 await status('transcribe',{src:'/_cdn/static/test.mp3',title:'Test',durationSeconds:1},503,{superjson:true});
 // Public listening works with or without an account. Private beta data remains gated.
 const user=(await sql`insert into users(email,display_name,role) values('other@muwa.invalid','Other','user') returning id`)[0];
 const session=randomBytes(32).toString('hex'),now=new Date();await sql`insert into sessions(id,user_id,expires_at) values(${session},${user.id},now()+interval '1 hour')`;
 const {setServerSession}=await import('../helpers/getSetServerSession');const response=new Response();await setServerSession(response,{id:session,createdAt:now.getTime(),lastAccessed:now.getTime()});
 await status('catalog/tracks',undefined,200,{cookie:response.headers.get('set-cookie')!.split(';')[0]});
 await status('admin/state',undefined,403,{cookie:response.headers.get('set-cookie')!.split(';')[0]});
 // General administrators still cannot use owner-only Telegram ingestion,
 // even when they are permitted into the beta and claim the owner's ID/email.
 await sql`update users set role='admin' where id=${user.id}`;
 process.env.MUWA_BETA_USER_IDS='1,'+user.id;
 const otherCookie=response.headers.get('set-cookie')!.split(';')[0];
 await status('admin/state',undefined,200,{cookie:otherCookie});
 await status('admin/action',{action:'lookup-telegram-import',source:importSource,ownerId:1,email:'owner@muwa.invalid'},403,{cookie:otherCookie});
 await status('admin/action',{action:'import-telegram-track',source:{...importSource,audioSha256:createHash('sha256').update(audio).digest('hex')},uploadId:randomUUID(),title:'Denied',artist:'Other',language:'und',duration:1,status:'draft'},403,{cookie:otherCookie});
 process.env.MUWA_BETA_USER_IDS='1';
 // Removing an administrator from the beta must also revoke draft previews,
 // despite the catalog's public GET middleware exception.
 await status('admin/action',{action:'set-status',trackId:id,revision:3,status:'draft'},200);
 const revokedPreview=await fetch(tracks[0].audio,{headers:{Cookie:otherCookie},redirect:'manual'});assert.equal(revokedPreview.status,404);await revokedPreview.arrayBuffer();checks++;
 const ownerPreview=await fetch(tracks[0].audio,{headers:{Cookie:cookie},redirect:'manual'});assert.equal(ownerPreview.status,302);await ownerPreview.arrayBuffer();checks++;
 const unpublished=await request('catalog/tracks',undefined,{cookie:''});assert.deepEqual((await unpublished.json()).tracks,[]);checks++;
 await status('catalog/captions?trackId='+id,undefined,404,{cookie:''});
 await status('auth/logout',{},200,{superjson:true});
 await status('catalog/tracks',undefined,200);
 console.log(JSON.stringify({runtimeChecks:checks,result:'passed',productionDatabaseTouched:false}));
} finally {
 await new Promise<void>(resolve=>server.close(()=>resolve()));await db.destroy();await sql.end();await fs.rm(root,{recursive:true,force:true});
}
