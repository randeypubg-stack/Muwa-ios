// Run on Beget with the private EnvironmentFile. Never print signed URLs/cookies.
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {upload,getUrl,remove} from '../dist/storage-check.mjs';
const origin=process.env.MUWA_PUBLIC_ORIGIN;
assert.equal(origin,'https://93.188.187.96');
const filename='qa/'+randomUUID()+'.wav';
const audio=Buffer.alloc(16044);audio.write('RIFF');audio.writeUInt32LE(audio.length-8,4);audio.write('WAVEfmt ',8);audio.writeUInt32LE(16,16);audio.writeUInt16LE(1,20);audio.writeUInt16LE(1,22);audio.writeUInt32LE(8000,24);audio.writeUInt32LE(16000,28);audio.writeUInt16LE(2,32);audio.writeUInt16LE(16,34);audio.write('data',36);audio.writeUInt32LE(16000,40);
try {
 const plan=await upload({visibility:'private',filename,contentType:'audio/wav',sizeBytes:audio.length});assert(plan.ok);
 assert.equal((await fetch(plan.presignedUrl,{method:'PUT',headers:plan.headers,body:audio})).status,201);
 const read=await getUrl({visibility:'private',filename});assert(read.ok);
 const response=await fetch(read.url,{headers:{Range:'bytes=0-43'}});assert.equal(response.status,206);assert.deepEqual(Buffer.from(await response.arrayBuffer()),audio.subarray(0,44));
 const full=Buffer.from(await(await fetch(read.url)).arrayBuffer());assert.equal(createHash('sha256').update(full).digest('hex'),createHash('sha256').update(audio).digest('hex'));
 for(const route of ['catalog/tracks','admin/state','premium/access']) {const r=await fetch(origin+'/_api/'+route);assert.equal(r.status,401);await r.arrayBuffer();}
 assert.equal((await fetch(origin+'/_health')).status,200);
 assert.equal((await fetch(origin+'/.env')).status,404);
 assert.equal((await fetch(origin+'/backend/helpers/db.tsx')).status,404);
 console.log(JSON.stringify({https:'trusted IP certificate',audioUpload:'passed',audioRange:'passed',audioIntegrity:'passed',anonymousAccess:'denied',sourceFiles:'not exposed',productionAccountsCreated:0}));
}finally{await remove({visibility:'private',filename});}
