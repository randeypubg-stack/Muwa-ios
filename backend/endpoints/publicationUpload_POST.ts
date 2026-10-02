import { db } from "../helpers/db";
import { upload } from "@floot/storage";
import superjson from "superjson";
import { NotAuthenticatedError } from "../helpers/getSetServerSession";
import { getServerUserSession } from "../helpers/getServerUserSession";
import { schema, type OutputType } from "./publicationUpload_POST.schema";

function safeExtension(name: string, contentType: string) {
  const fromName = name.split(".").pop()?.toLowerCase().replace(/[^a-z0-9]/g, "") || "";
  if (fromName && fromName.length <= 8) return fromName;
  const map: Record<string,string> = {
    "audio/mpeg": "mp3",
    "audio/mp4": "m4a",
    "audio/x-m4a": "m4a",
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
    "application/json": "json",
  };
  return map[contentType] || "bin";
}

export async function handle(request: Request) {
  try {
    const {user} = await getServerUserSession(request);
    const input = schema.parse(superjson.parse(await request.text()));

    if (input.part === "submission" && input.contentType !== "application/json") {
      return new Response(superjson.stringify({ error: "Submission metadata must be JSON" }), { status: 400 });
    }
    if (input.part === "submission" && input.sizeBytes > 256 * 1024) {
      return new Response(superjson.stringify({ error: "Submission metadata is too large" }), { status: 400 });
    }
    if (input.part === "audio" && !input.contentType.startsWith("audio/")) {
      return new Response(superjson.stringify({ error: "Audio file required" }), { status: 400 });
    }
    if (input.part === "cover" && !input.contentType.startsWith("image/")) {
      return new Response(superjson.stringify({ error: "Image file required" }), { status: 400 });
    }

    const ext = input.part === "submission" ? "json" : safeExtension(input.originalName, input.contentType);
    const filename = `publications/${input.draftId}/${input.part}.${ext}`;
    const allowed = await db.transaction().execute(async tx => {
      await tx.insertInto("publicationDrafts").values({id:input.draftId,userId:user.id}).onConflict(oc=>oc.column("id").doNothing()).execute();
      const draft=await tx.selectFrom("publicationDrafts").select(["userId","status"]).where("id","=",input.draftId).forUpdate().executeTakeFirstOrThrow();
      if(draft.userId!==user.id || draft.status!=="uploading")return false;
      if(input.part!=="submission")await tx.updateTable("publicationDrafts").set({
        ...(input.part==="audio"?{audioKey:filename}:{coverKey:filename}),updatedAt:new Date()
      }).where("id","=",input.draftId).execute();
      return true;
    });
    if(!allowed)return new Response(superjson.stringify({error:"This draft is unavailable for upload"}),{status:403,headers:{"Content-Type":"application/json"}});
    const result = await upload({
      visibility: "private",
      filename,
      contentType: input.contentType,
      sizeBytes: input.sizeBytes,
      expiresInSeconds: 900,
    });

    if (!result.ok) {
      return new Response(superjson.stringify({ error: result.error.message, code: result.error.code }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const output: OutputType = {
      storageKey: filename,
      presignedUrl: result.presignedUrl,
    };
    return new Response(superjson.stringify(output), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    if (error instanceof NotAuthenticatedError) {
      return new Response(superjson.stringify({ error: "Not authenticated" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }
    const message = error instanceof Error ? error.message : "Unable to prepare publication upload";
    return new Response(superjson.stringify({ error: message }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }
}
