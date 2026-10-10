import { createHash, randomBytes } from "node:crypto";
import { z } from "zod";
import { db } from "../../helpers/db";
import { sql } from "kysely";
import { generatePasswordHash } from "../../helpers/generatePasswordHash";
import { guardMutation, readJSONLimited, secureJSON, SecurityError } from "../../helpers/requestSecurity";
import { SessionExpirationSeconds, setServerSession } from "../../helpers/getSetServerSession";
const schema = z.object({token:z.string().regex(/^[a-f0-9]{64}$/),password:z.string().min(12).max(72).refine(p=>Buffer.byteLength(p)<=72)}).strict();
export async function handle(request:Request) {
  try {
    guardMutation(request);
    const input=schema.parse(await readJSONLimited(request,4096));
    const tokenHash=createHash("sha256").update(input.token).digest("hex");
    const existing=await db.selectFrom("ownerSetup").select("id").where("tokenHash","=",tokenHash).where("consumedAt","is",null).where("expiresAt",">",new Date()).executeTakeFirst();
    if(!existing)return secureJSON({error:"Ссылка настройки истекла или уже использована."},403);
    const hash=await generatePasswordHash(input.password);
    const sessionId=randomBytes(32).toString("hex"),now=new Date();
    const user=await db.transaction().execute(async tx=>{
      await sql`select pg_advisory_xact_lock(hashtextextended('muwa-owner-setup',0))`.execute(tx);
      const setup=await tx.selectFrom("ownerSetup").selectAll().where("tokenHash","=",tokenHash).where("consumedAt","is",null).where("expiresAt",">",now).forUpdate().executeTakeFirst();
      const account=await tx.selectFrom("users").select("id").limit(1).executeTakeFirst();
      if(!setup || account)throw new SecurityError("Настройка уже завершена или ссылка истекла.",403);
      const u=await tx.insertInto("users").values({email:setup.email,displayName:"Владелец Muwa",role:"admin"}).returning(["id","email","displayName","avatarUrl","role"]).executeTakeFirstOrThrow();
      await tx.insertInto("userPasswords").values({userId:u.id,passwordHash:hash}).execute();
      await tx.insertInto("premiumCodeAdmins").values({userId:u.id}).execute();
      await tx.insertInto("sessions").values({id:sessionId,userId:u.id,createdAt:now,lastAccessed:now,expiresAt:new Date(now.getTime()+SessionExpirationSeconds*1000)}).execute();
      await tx.updateTable("ownerSetup").set({consumedAt:now}).where("id","=",true).execute();
      return u;
    });
    const response=secureJSON({user});
    await setServerSession(response,{id:sessionId,createdAt:now.getTime(),lastAccessed:now.getTime()});
    return response;
  }catch(e){return secureJSON({error:e instanceof SecurityError?e.message:"Не удалось завершить настройку. Пароль: от 12 символов, максимум 72 байта."},e instanceof SecurityError?e.status:400);}
}
