import {createHash,randomBytes,randomUUID} from 'node:crypto';
import {sql} from 'kysely';
import {db} from './db';
import {getServerUserSession} from './getServerUserSession';
import {NotAuthenticatedError,setServerSession} from './getSetServerSession';
import type {schema as inputSchema,PremiumStatus,GiftCode} from '../endpoints/premium/access_POST.schema';

const json=(body:unknown,status=200)=>Response.json(body,{status,headers:{'Cache-Control':'no-store'}});
const fail=(error:string,status=400)=>json({error},status);
async function status(userId:number):Promise<PremiumStatus> {
  const access=await db.selectFrom('premiumAccess').selectAll().where('userId','=',userId).executeTakeFirst();
  const admin=await db.selectFrom('premiumCodeAdmins').select('userId').where('userId','=',userId).executeTakeFirst();
  return {userId,isPremium:!!access && (access.expiresAt===null || access.expiresAt>new Date()),expiresAt:access?.expiresAt?.toISOString()??null,canManageCodes:!!admin};
}
async function handle(request:Request,schema:typeof inputSchema):Promise<Response> {
  if(!request.headers.get('content-type')?.includes('application/json'))return fail('Нужен JSON-запрос.',415);
  const origin=request.headers.get('origin');
  if(origin && !['https://muwa-app.floot.app','https://20d2f317-3710-4331-80ee-ea6072056928.sandbox.floot.app'].includes(origin))return fail('Недопустимый источник запроса.',403);
  try {
    const {user,session}=await getServerUserSession(request);
    const parsed=schema.safeParse(await request.json().catch(()=>null));
    if(!parsed.success)return fail('Проверьте введённые данные.');
    const input=parsed.data;
    const current=await status(user.id);
    let extra:object={};
    if(input.action==='redeem') {
      // Committed separately: rejected codes must also consume a rate-limit attempt.
      const limit=await sql`insert into premium_code_limits(user_id) values(${user.id}) on conflict(user_id) do update set attempts=case when premium_code_limits.window_start < now()-interval '1 hour' then 1 else premium_code_limits.attempts+1 end,window_start=case when premium_code_limits.window_start < now()-interval '1 hour' then now() else premium_code_limits.window_start end where premium_code_limits.window_start < now()-interval '1 hour' or premium_code_limits.attempts<20 returning user_id`.execute(db);
      if(!limit.rows.length)return fail('Слишком много попыток. Повторите через час.',429);
      const normalized=input.code.toUpperCase().replace(/[\s-]/g,'');
      if(!/^MUWA[0-9A-F]{24}$/.test(normalized))return fail('Промокод недействителен или срок активации истёк.');
      const hash=createHash('sha256').update(normalized).digest('hex');
      const outcome=await db.transaction().execute(async tx=>{
        // Serialize codes for one account, then claim this code. Prevent lost extensions and over-redemption.
        await tx.selectFrom('users').select('id').where('id','=',user.id).forUpdate().executeTakeFirstOrThrow();
        const code=await tx.selectFrom('premiumCodes').selectAll().where('codeHash','=',hash).forUpdate().executeTakeFirst();
        if(!code)return 'invalid';
        const prior=await tx.selectFrom('premiumRedemptions').select('codeId').where('codeId','=',code.id).where('userId','=',user.id).executeTakeFirst();
        if(prior)return 'already';
        if(code.disabled || code.expiresAt<=new Date() || code.uses>=code.maxUses)return 'invalid';
        const access=await tx.selectFrom('premiumAccess').selectAll().where('userId','=',user.id).executeTakeFirst();
        if(access && access.expiresAt===null)return 'permanent';
        const expiresAt=new Date(Math.max(Date.now(),access?.expiresAt?.getTime()??0)+code.durationDays*86400000);
        await tx.insertInto('premiumAccess').values({userId:user.id,expiresAt}).onConflict(oc=>oc.column('userId').doUpdateSet({expiresAt,updatedAt:new Date()})).execute();
        await tx.insertInto('premiumRedemptions').values({userId:user.id,codeId:code.id}).execute();
        await tx.updateTable('premiumCodes').set({uses:code.uses+1}).where('id','=',code.id).execute();
        return 'redeemed';
      });
      if(outcome==='invalid')return fail('Промокод недействителен, исчерпан или срок активации истёк.');
      if(outcome==='permanent')return fail('У вас уже бессрочный Premium. Подарите этот код другу.',409);
      extra={alreadyRedeemed:outcome==='already'};
    } else if(input.action!=='status') {
      if(!current.canManageCodes)return fail('Создавать и управлять кодами может только владелец.',403);
      if(input.action==='create') {
        const count=await db.selectFrom('premiumCodes').select(eb=>eb.fn.countAll<string>().as('count')).where('createdBy','=',user.id).where('createdAt','>',new Date(Date.now()-3600000)).executeTakeFirstOrThrow();
        if(Number(count.count)>=50)return fail('Лимит создания кодов на час достигнут.',429);
        const token=randomBytes(12).toString('hex').toUpperCase();
        const code='MUWA-'+token.match(/.{1,4}/g)!.join('-');
        await db.insertInto('premiumCodes').values({id:randomUUID(),codeHash:createHash('sha256').update('MUWA'+token).digest('hex'),label:input.label,durationDays:input.durationDays,maxUses:input.maxUses,expiresAt:new Date(Date.now()+input.validDays*86400000),createdBy:user.id}).execute();
        extra={code}; // Full code is returned once; only its hash is stored.
      } else if(input.action==='disable') {
        await db.updateTable('premiumCodes').set({disabled:true}).where('id','=',input.id).execute();
      }
      const rows=await db.selectFrom('premiumCodes').select(['id','label','durationDays','maxUses','uses','expiresAt','disabled']).orderBy('createdAt','desc').limit(100).execute();
      const codes:GiftCode[]=rows.map(row=>({...row,expiresAt:row.expiresAt.toISOString()}));
      extra={...extra,codes};
    }
    const response=json({...await status(user.id),...extra});
    await setServerSession(response,{...session,lastAccessed:session.lastAccessed.getTime()});
    return response;
  } catch(error) {
    if(error instanceof NotAuthenticatedError)return fail('Войдите в аккаунт Muwa.',401);
    console.error('Premium request failed',error instanceof Error?error.name:'unknown');
    return fail('Сервис временно недоступен. Повторите позже.',503);
  }
}
export const premiumService={handle,status};

