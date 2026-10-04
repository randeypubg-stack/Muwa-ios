import { Hono } from "hono";
import { handleStorage } from "../helpers/storage";
import { publicOrigin, betaUserAllowed } from "../helpers/runtimeConfig";
import { getServerUserSession } from "../helpers/getServerUserSession";
import { NotAuthenticatedError } from "../helpers/getSetServerSession";
import { secureJSON } from "../helpers/requestSecurity";
import { db } from "../helpers/db";
import { sql } from "kysely";
import { handle as login } from "../endpoints/auth/login_with_password_POST";
import { handle as register } from "../endpoints/auth/register_with_password_POST";
import { handle as logout } from "../endpoints/auth/logout_POST";
import { handle as session } from "../endpoints/auth/session_GET";
import { handle as ownerSetup } from "../endpoints/auth/owner_setup_POST";
import { handle as catalog } from "../endpoints/catalog/tracks_GET";
import { handle as captions } from "../endpoints/catalog/captions_GET";
import { handle as media } from "../endpoints/catalog/media_GET";
import { handle as adminState } from "../endpoints/admin/state_GET";
import { handle as adminAction } from "../endpoints/admin/action_POST";
import { handle as diagnostics } from "../endpoints/diagnostics/events_POST";
import { handle as premium } from "../endpoints/premium/access_POST";
import { handle as publication } from "../endpoints/publicationUpload_POST";
import { handle as original } from "../endpoints/subtitles/original_POST";
import { handle as translate } from "../endpoints/subtitles/translate_POST";
import { handle as transcribe } from "../endpoints/transcribe_POST";
export function createApp() {
  publicOrigin();
  const app=new Hono();
  app.onError((_error,c)=>{console.error(JSON.stringify({event:"request_failed",path:c.req.path}));return secureJSON({error:"Сервис временно недоступен."},503);});
  app.get("/_health",async()=>{
    try { await sql`select 1`.execute(db); return secureJSON({status:"ok",service:"Muwa"}); }
    catch { return secureJSON({status:"unavailable",service:"Muwa"},503); }
  });
  app.all("/_storage/file",c=>handleStorage(c.req.raw));
  app.use("/_api/*",async(c,next)=>{
    const open=["/_api/auth/login_with_password","/_api/auth/logout","/_api/auth/session","/_api/auth/owner_setup"];
    if(c.req.path==="/_api/auth/register_with_password")return secureJSON({message:"Закрытый тест Muwa. Регистрация пока недоступна."},403);
    if(!open.includes(c.req.path)){
      try{const {user}=await getServerUserSession(c.req.raw);if(!betaUserAllowed(user.id))return secureJSON({error:"Доступ к закрытому тесту не предоставлен."},403);}
      catch(e){return secureJSON({error:e instanceof NotAuthenticatedError?"Войдите в Muwa.":"Сервис временно недоступен."},e instanceof NotAuthenticatedError?401:503);}
    }
    await next();
    if(!open.includes(c.req.path)){c.header("Cache-Control","private, no-store");c.header("Vary","Cookie");}
  });
  const routes:["get"|"post",string,(request:Request)=>Promise<Response>][]=[
    ["post","auth/login_with_password",login],["post","auth/register_with_password",register],
    ["post","auth/logout",logout],["get","auth/session",session],["post","auth/owner_setup",ownerSetup],
    ["get","catalog/tracks",catalog],["get","catalog/captions",captions],["get","catalog/media",media],
    ["get","admin/state",adminState],["post","admin/action",adminAction],["post","diagnostics/events",diagnostics],
    ["post","premium/access",premium],["post","publicationUpload",publication],
    ["post","subtitles/original",original],["post","subtitles/translate",translate],["post","transcribe",transcribe],
  ];
  for(const [method,path,handler] of routes)app[method]("/_api/"+path,c=>handler(c.req.raw));
  app.notFound(()=>secureJSON({error:"Не найдено."},404));
  return app;
}
