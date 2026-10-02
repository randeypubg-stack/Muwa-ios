const fs=require('node:fs'),path=require('node:path');
const {db,testPool}=require('./db');
const {adminService}=require('./adminService');
const storage=require('./testStorage');
const root=path.resolve(__dirname,'../..');
async function request(user,body,origin){return adminService.handle(new Request('https://muwa-app.floot.app/_api/admin/action',{method:'POST',headers:{'Content-Type':'application/json','x-fixture-user':String(user),...(origin?{Origin:origin}:{})},body:JSON.stringify(body)}),'POST');}
const meta={title:'Fixture',artist:'Muwa',language:'ar',duration:10,status:'draft'};
async function prepared(user=1){const r=await request(user,{action:'prepare-upload',files:[{part:'audio',contentType:'audio/mpeg',sizeBytes:32}]});expect(r.status).toBe(200);const p=await r.json();for(const f of p.files)storage.files.set(f.filename,{sizeBytes:f.sizeBytes});return p;}
async function create(){const p=await prepared();const r=await request(1,{action:'save-track',uploadId:p.uploadId,...meta});expect(r.status).toBe(200);return (await r.json()).trackId;}
describe('Muwa admin transactions in disposable PostgreSQL',()=>{
 beforeAll(async()=>{
  await testPool.query('CREATE TABLE IF NOT EXISTS users (id integer PRIMARY KEY); ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name text; INSERT INTO users(id) VALUES(1),(2),(3) ON CONFLICT DO NOTHING');
  await testPool.query(fs.readFileSync(path.join(root,'admin-migration.sql'),'utf8'));
  await testPool.query(fs.readFileSync(path.join(root,'admin-migration.sql'),'utf8'));
 });
 beforeEach(async()=>{await testPool.query('TRUNCATE admin_audit_events,publication_drafts,catalog_uploads,catalog_tracks CASCADE');storage.files.clear();});
 it('rejects guests, ordinary accounts and cross-site mutations',async()=>{
  expect((await request(0,{action:'refresh-submissions'})).status).toBe(401);
  expect((await request(2,{action:'refresh-submissions'})).status).toBe(403);
  expect((await request(1,{action:'refresh-submissions'},'https://other.example')).status).toBe(403);
  expect((await testPool.query('SELECT * FROM admin_audit_events')).rows.length).toBe(0);
 });
 it('verifies actual upload size and consumes plans exactly once',async()=>{
  const p=await prepared();storage.files.set(p.files[0].filename,{sizeBytes:1});
  expect((await request(1,{action:'save-track',uploadId:p.uploadId,...meta})).status).toBe(400);
  storage.files.set(p.files[0].filename,{sizeBytes:32});
  expect((await request(1,{action:'save-track',uploadId:p.uploadId,...meta})).status).toBe(200);
  expect((await request(1,{action:'save-track',uploadId:p.uploadId,...meta})).status).toBe(409);
  expect((await testPool.query('SELECT * FROM catalog_tracks')).rows.length).toBe(1);
 });
 it('serializes concurrent revisions and journals only committed changes',async()=>{
  const id=await create();const values=await Promise.all(['published','archived'].map(status=>request(1,{action:'set-status',trackId:id,revision:1,status})));
  expect(values.map(r=>r.status).sort()).toEqual([200,409]);
  expect((await testPool.query('SELECT revision FROM catalog_tracks')).rows[0].revision).toBe(2);
  expect((await testPool.query('SELECT * FROM admin_audit_events')).rows.length).toBe(2);
 });
 it('validates caption duration and stores JSON arrays once',async()=>{
  const id=await create();
  const captions=[{start:0,end:11,ar:'نص',ru:'Перевод',en:'Text'}];
  expect((await request(1,{action:'save-captions',trackId:id,revision:1,captions})).status).toBe(400);
  captions[0].end=2;
  expect((await request(1,{action:'save-captions',trackId:id,revision:1,captions})).status).toBe(200);
  const row=(await testPool.query('SELECT captions,captions_revision FROM catalog_tracks')).rows[0];expect(Array.isArray(row.captions)).toBeTrue();expect(row.captions_revision).toBe(1);
 });
 it('invalidates old captions when audio is replaced',async()=>{
  const id=await create();await request(1,{action:'save-captions',trackId:id,revision:1,captions:[{start:0,end:2,ar:'نص',ru:'',en:''}]});
  const r=await request(1,{action:'prepare-upload',trackId:id,revision:2,files:[{part:'audio',contentType:'audio/mpeg',sizeBytes:40}]});const p=await r.json();storage.files.set(p.files[0].filename,{sizeBytes:40});
  expect((await request(1,{action:'save-track',trackId:id,revision:2,uploadId:p.uploadId,...meta})).status).toBe(200);
  const row=(await testPool.query('SELECT captions,captions_revision FROM catalog_tracks')).rows[0];expect(row.captions).toEqual([]);expect(row.captions_revision).toBe(2);
 });
 it('keeps uploading submissions unapproved and atomically claims a ready submission',async()=>{
  const id='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';await testPool.query("INSERT INTO publication_drafts(id,user_id,status,audio_key,title,artist) VALUES($1,2,'uploading',$2,'Fixture','Muwa')",[id,`publications/${id}/audio.mp3`]);storage.files.set(`publications/${id}/audio.mp3`,{sizeBytes:32});
  expect((await request(1,{action:'prepare-approval',submissionId:id,revision:1})).status).toBe(409);
  await testPool.query("UPDATE publication_drafts SET status='pending' WHERE id=$1",[id]);
  const r=await request(1,{action:'prepare-approval',submissionId:id,revision:1});const p=await r.json();storage.files.set(p.files[0].filename,{sizeBytes:32});
  const body={action:'approve-submission',submissionId:id,revision:1,uploadId:p.uploadId,title:'Approved',artist:'Muwa',language:'ar',duration:10};
  const results=await Promise.all([request(1,body),request(1,body)]);expect(results.map(r=>r.status).sort()).toEqual([200,409]);
  expect((await testPool.query('SELECT * FROM catalog_tracks')).rows.length).toBe(1);
  expect((await testPool.query('SELECT status FROM publication_drafts')).rows[0].status).toBe('published');
 });
 it('rejects expired upload plans and blocks publication without audio',async()=>{
  const p=await prepared();await testPool.query("UPDATE catalog_uploads SET expires_at=now()-interval '1 second' WHERE id=$1",[p.uploadId]);
  expect((await request(1,{action:'save-track',uploadId:p.uploadId,...meta})).status).toBe(409);
  await testPool.query("INSERT INTO catalog_tracks(id,title,artist) VALUES('empty','Empty','Muwa')");
  expect((await request(1,{action:'set-status',trackId:'empty',revision:1,status:'published'})).status).toBe(400);
 });
});
