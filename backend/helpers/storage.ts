import { createHmac, createHash, timingSafeEqual, randomUUID } from "node:crypto";
import { promises as fs, createReadStream } from "node:fs";
import path from "node:path";
import { Readable } from "node:stream";
import { publicOrigin, storageRoot } from "./runtimeConfig";
import { secureJSON, SecurityError } from "./requestSecurity";

type Visibility = "private" | "public";
type ObjectKey = { visibility: Visibility; filename: string };
type Metadata = { sizeBytes: number; contentType: string; etag: string };
type Ticket = ObjectKey & { operation: "read" | "write"; exp: number; sizeBytes?: number; contentType?: string };
const MAX_OBJECT = 100 * 1024 * 1024;
const mimeTypes = new Set(["audio/mpeg", "audio/mp4", "audio/x-m4a", "audio/wav", "image/jpeg", "image/png", "image/webp", "application/json"]);
let activeUploads = 0;
function keyValid(key: ObjectKey) {
  return ["private", "public"].includes(key.visibility) && typeof key.filename === "string" && key.filename.length > 0 &&
    key.filename.length <= 240 && /^[A-Za-z0-9_./-]+$/.test(key.filename) &&
    key.filename.split("/").every(p => p.length > 0 && !p.startsWith("."));
}
function secret() {
  const value = process.env.MUWA_STORAGE_SECRET;
  if (!value || Buffer.byteLength(value) < 32) throw new Error("Private storage signing is not configured");
  return value;
}
function signedURL(ticket: Ticket) {
  if (!keyValid(ticket)) throw new SecurityError("Недопустимый файл.");
  const encoded = Buffer.from(JSON.stringify(ticket)).toString("base64url");
  const signature = createHmac("sha256", secret()).update(encoded).digest("hex");
  return `${publicOrigin()}/_storage/file?token=${encoded}.${signature}`;
}
function readTicket(request: Request): Ticket {
  const token = new URL(request.url).searchParams.get("token") ?? "";
  if (token.length > 2048 || !/^[A-Za-z0-9_-]+\.[a-f0-9]{64}$/.test(token)) throw new SecurityError("Ссылка недействительна.", 403);
  const [encoded, signature] = token.split(".");
  const actual = createHmac("sha256", secret()).update(encoded).digest();
  if (!timingSafeEqual(actual, Buffer.from(signature, "hex"))) throw new SecurityError("Ссылка недействительна.", 403);
  let ticket: Ticket;
  try { ticket = JSON.parse(Buffer.from(encoded, "base64url").toString("utf8")); }
  catch { throw new SecurityError("Ссылка недействительна.", 403); }
  if (!keyValid(ticket) || !["read", "write"].includes(ticket.operation) || !Number.isSafeInteger(ticket.exp) || ticket.exp <= Math.floor(Date.now()/1000))
    throw new SecurityError("Ссылка истекла или недействительна.", 403);
  return ticket;
}
async function objectPaths(key: ObjectKey, create = false) {
  if (!keyValid(key)) throw new SecurityError("Недопустимый файл.");
  const root = storageRoot();
  const rootInfo = await fs.lstat(root);
  if (!rootInfo.isDirectory() || rootInfo.isSymbolicLink()) throw new Error("Invalid private storage directory");
  const directory = path.join(root, key.visibility, path.dirname(key.filename));
  const metaDirectory = path.join(root, ".metadata", key.visibility, path.dirname(key.filename));
  for (const folder of [directory, metaDirectory]) {
    let current = root;
    for (const part of path.relative(root, folder).split(path.sep).filter(Boolean)) {
      current = path.join(current, part);
      if (create) await fs.mkdir(current, {mode:0o700}).catch(e => { if (e.code !== "EEXIST") throw e; });
      try {
        const info = await fs.lstat(current);
        if (!info.isDirectory() || info.isSymbolicLink()) throw new Error("Unsafe storage directory");
      } catch(e) { if ((e as NodeJS.ErrnoException).code !== "ENOENT") throw e; }
    }
  }
  return { file: path.join(directory, path.basename(key.filename)), metadata: path.join(metaDirectory, path.basename(key.filename)+".json") };
}
export async function getInfo(key: ObjectKey) {
  try {
    const paths = await objectPaths(key), info = await fs.lstat(paths.file);
    if (!info.isFile() || info.isSymbolicLink()) throw new Error("Unsafe storage object");
    const metaInfo = await fs.lstat(paths.metadata);
    if (!metaInfo.isFile() || metaInfo.isSymbolicLink() || metaInfo.size > 2048) throw new Error("Invalid object metadata");
    const metadata: Metadata = JSON.parse(await fs.readFile(paths.metadata, "utf8"));
    if (metadata.sizeBytes !== info.size || !/^"[a-f0-9]{64}"$/.test(metadata.etag) || !mimeTypes.has(metadata.contentType)) throw new Error("Invalid object metadata");
    return { ok: true as const, exists: true as const, ...metadata };
  } catch(e) {
    if ((e as NodeJS.ErrnoException).code === "ENOENT") return {ok:true as const,exists:false as const};
    return {ok:false as const, error:"Хранилище недоступно."};
  }
}
export async function getUrl(key: ObjectKey & {expiresInSeconds?: number}) {
  if (!keyValid(key)) return {ok:false as const,error:"Недопустимый файл."};
  return {ok:true as const,url:signedURL({...key,operation:"read",exp:Math.floor(Date.now()/1000)+Math.min(86400,Math.max(30,key.expiresInSeconds??300))})};
}
export async function upload(input: ObjectKey & {sizeBytes:number;contentType:string;ifAbsent?:boolean;expiresInSeconds?:number}) {
  if (!keyValid(input) || !Number.isSafeInteger(input.sizeBytes) || input.sizeBytes <= 0 || input.sizeBytes > MAX_OBJECT || !mimeTypes.has(input.contentType))
    return {ok:false as const,error:"Недопустимый файл."};
  const existing = await getInfo(input);
  if (!existing.ok || existing.exists) return {ok:false as const,error:"Файл уже существует или недоступен."};
  const exp = Math.floor(Date.now()/1000)+Math.min(900,Math.max(30,input.expiresInSeconds??900));
  const ticket:Ticket={visibility:input.visibility,filename:input.filename,operation:"write",sizeBytes:input.sizeBytes,contentType:input.contentType,exp};
  const read=await getUrl(input);
  if(!read.ok)return read;
  return {ok:true as const,presignedUrl:signedURL(ticket),url:read.url,headers:{"Content-Type":input.contentType,"Content-Length":String(input.sizeBytes),"If-None-Match":"*"}};
}
export async function remove(key:ObjectKey) {
  try {
    const paths=await objectPaths(key);
    for(const p of [paths.file,paths.metadata])await fs.unlink(p).catch(e=>{if(e.code!=="ENOENT")throw e;});
    return {ok:true as const};
  }catch{return {ok:false as const,error:"Не удалось удалить файл."};}
}
export async function listFolder(input:{visibility:Visibility;key:string;continuationToken?:string}) {
  if(input.continuationToken)return {ok:false as const,error:"Недопустимый указатель."};
  const key=input.key.replace(/\/$/,"");
  if(!keyValid({visibility:input.visibility,filename:key+"/marker"}))return {ok:false as const,error:"Недопустимый каталог."};
  try {
    const guarded=await objectPaths({visibility:input.visibility,filename:key+"/marker"});
    const entries=await fs.readdir(path.dirname(guarded.file),{withFileTypes:true});
    return {ok:true as const,folders:entries.filter(e=>e.isDirectory()&&!e.name.startsWith(".")).map(e=>key+"/"+e.name+"/").sort(),
      files:entries.filter(e=>e.isFile()&&!e.name.startsWith(".")).map(e=>({key:key+"/"+e.name})),nextContinuationToken:undefined};
  }catch(e){if((e as NodeJS.ErrnoException).code==="ENOENT")return {ok:true as const,folders:[],files:[],nextContinuationToken:undefined};return {ok:false as const,error:"Хранилище недоступно."};}
}
async function writeObject(request:Request,ticket:Ticket) {
  const expected=ticket.sizeBytes;
  if(!Number.isSafeInteger(expected)||!expected||expected>MAX_OBJECT||!ticket.contentType||!mimeTypes.has(ticket.contentType))throw new SecurityError("Недопустимая загрузка.",403);
  if(request.headers.get("if-none-match")!=="*" || request.headers.get("content-type")?.split(";")[0].trim().toLowerCase()!==ticket.contentType)
    throw new SecurityError("Параметры загрузки изменены.",400);
  const advertised=request.headers.get("content-length");
  if(advertised && (!/^\d+$/.test(advertised)||Number(advertised)!==expected))throw new SecurityError("Размер файла изменён.",400);
  if(!request.body)throw new SecurityError("Файл отсутствует.");
  if(activeUploads>=4)throw new SecurityError("Хранилище занято. Повторите позже.",503);
  activeUploads++;
  let temporary:string|undefined, published:string|undefined, reader:ReadableStreamDefaultReader<Uint8Array>|undefined;
  try{
    const space=await fs.statfs(storageRoot());
    if(space.bavail*space.bsize < expected+5*1024**3)throw new SecurityError("Мало свободного места на сервере.",507);
    const paths=await objectPaths(ticket,true);
    temporary=path.join(path.dirname(paths.file),".upload-"+randomUUID());
    const output=await fs.open(temporary,"wx",0o600), hash=createHash("sha256");
    let size=0;
    reader=request.body.getReader();
    try{
      while(true){
        const item=await reader.read();if(item.done)break;
        size+=item.value.byteLength;if(size>expected)throw new SecurityError("Файл слишком большой.",413);
        hash.update(item.value);
        let written=0;
        while(written<item.value.byteLength){const result=await output.write(item.value,written,item.value.byteLength-written);if(result.bytesWritten<=0)throw new Error("Incomplete file write");written+=result.bytesWritten;}
      }
      if(size!==expected)throw new SecurityError("Файл загружен не полностью.",400);
      await output.sync();
    }finally{await output.close();}
    try{await fs.link(temporary,paths.file);published=paths.file;}
    catch(e){if((e as NodeJS.ErrnoException).code==="EEXIST")throw new SecurityError("Файл уже существует.",409);throw e;}
    const metadata:Metadata={sizeBytes:size,contentType:ticket.contentType,etag:'"'+hash.digest("hex")+'"'};
    await fs.writeFile(paths.metadata,JSON.stringify(metadata),{flag:"wx",mode:0o600});
    published=undefined;
    return new Response(null,{status:201,headers:{ETag:metadata.etag,"Cache-Control":"no-store"}});
  }finally{
    if(reader){await reader.cancel().catch(()=>{});reader.releaseLock();}
    if(temporary)await fs.unlink(temporary).catch(()=>{});
    if(published)await fs.unlink(published).catch(()=>{});
    activeUploads--;
  }
}
async function readObject(request:Request,ticket:Ticket){
  const info=await getInfo(ticket);
  if(!info.ok)throw new SecurityError("Файл недоступен.",503);
  if(!info.exists)throw new SecurityError("Файл не найден.",404);
  const match=request.headers.get("if-match");
  if(match && match!==info.etag && match!=="*")return new Response(null,{status:412});
  const headers=new Headers({"Content-Type":info.contentType,ETag:info.etag,"Accept-Ranges":"bytes","Cache-Control":"private, no-store","X-Content-Type-Options":"nosniff","Referrer-Policy":"no-referrer"});
  let start=0,end=info.sizeBytes-1,status=200;
  const range=request.headers.get("range"),ifRange=request.headers.get("if-range");
  if(range && (!ifRange || ifRange===info.etag)){
    const match=/^bytes=(\d*)-(\d*)$/.exec(range);
    if(!match || (!match[1]&&!match[2]))return new Response(null,{status:416,headers:{"Content-Range":`bytes */${info.sizeBytes}`}});
    if(!match[1]){const suffix=Number(match[2]);if(!Number.isSafeInteger(suffix)||suffix<=0)return new Response(null,{status:416});start=Math.max(0,info.sizeBytes-suffix);}
    else{start=Number(match[1]);end=match[2]?Math.min(info.sizeBytes-1,Number(match[2])):end;}
    if(!Number.isSafeInteger(start)||!Number.isSafeInteger(end)||start> end||start>=info.sizeBytes)return new Response(null,{status:416,headers:{"Content-Range":`bytes */${info.sizeBytes}`}});
    status=206;headers.set("Content-Range",`bytes ${start}-${end}/${info.sizeBytes}`);
  }
  headers.set("Content-Length",String(end-start+1));
  if(request.method==="HEAD")return new Response(null,{status,headers});
  const paths=await objectPaths(ticket);
  const stream=createReadStream(paths.file,{start,end,flags:"r"});
  return new Response(Readable.toWeb(stream) as ReadableStream,{status,headers});
}
export async function handleStorage(request:Request){
  try{
    const ticket=readTicket(request);
    if(ticket.operation==="write" && request.method==="PUT")return await writeObject(request,ticket);
    if(ticket.operation==="read" && ["GET","HEAD"].includes(request.method))return await readObject(request,ticket);
    return secureJSON({error:"Метод недоступен."},405);
  }catch(e){return secureJSON({error:e instanceof SecurityError?e.message:"Хранилище временно недоступно."},e instanceof SecurityError?e.status:503);}
}
