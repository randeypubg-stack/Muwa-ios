import postgres from "postgres";
import {randomBytes,createHash} from "node:crypto";
import {promises as fs} from "node:fs";
const connection=process.env.MUWA_DATABASE_URL,origin=process.env.MUWA_PUBLIC_ORIGIN;
if(!connection||!origin||new URL(origin).protocol!=="https:")throw new Error("Server configuration is required");
const sql=postgres(connection,{max:1,prepare:false});
try{
  const token=randomBytes(32).toString("hex"),hash=createHash("sha256").update(token).digest("hex");
  const email=(process.env.MUWA_OWNER_EMAIL??"randey.pubg@gmail.com").trim().toLowerCase();
  if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))throw new Error("Invalid owner email");
  const output=process.env.MUWA_OWNER_SETUP_LINK_FILE??"/var/lib/muwa/owner-setup-link.txt";
  const result=await sql.begin(async tx=>{
    await tx`select pg_advisory_xact_lock(hashtextextended('muwa-owner-setup',0))`;
    if((await tx`select id from users limit 1`).length)return "already_configured";
    const existing=await tx`select id from owner_setup where consumed_at is null and expires_at>now()`;
    if(existing.length)return "already_prepared";
    await tx`insert into owner_setup(id,token_hash,email,expires_at) values(true,${hash},${email},now()+interval '24 hours') on conflict(id) do update set token_hash=excluded.token_hash,email=excluded.email,expires_at=excluded.expires_at,consumed_at=null`;
    return "created";
  });
  if(result==="created")await fs.writeFile(output,new URL("/admin",origin).href+"#setup="+token+"\n",{mode:0o600});
  console.log(JSON.stringify({ownerSetup:result,privateLinkFile:output,secretPrinted:false}));
}finally{await sql.end();}
