import { serve } from "@hono/node-server";
import { createApp } from "./app";
import { db } from "../helpers/db";
import { Server } from "node:http";
const port=Number(process.env.MUWA_API_PORT??3000);
if(!Number.isInteger(port)||port<1024||port>65535)throw new Error("Invalid API port");
const server=serve({fetch:createApp().fetch,hostname:"127.0.0.1",port});
if (server instanceof Server) {
  server.requestTimeout=120000;
  server.headersTimeout=15000;
  server.keepAliveTimeout=5000;
}
console.info(JSON.stringify({event:"started",service:"Muwa",port}));
let closing=false;
async function shutdown(){
  if(closing)return; closing=true;
  await new Promise<void>(resolve => server.close(() => resolve()));
  await db.destroy(); process.exitCode=0;
}
process.on("SIGTERM",shutdown);process.on("SIGINT",shutdown);
