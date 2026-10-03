// adapt this to the database schema and helpers if necessary
import { db } from "../../helpers/db";
import { sql } from "kysely";
import { schema } from "./register_with_password_POST.schema";
import { randomBytes } from "crypto";
import {
  setServerSession,
  SessionExpirationSeconds,
} from "../../helpers/getSetServerSession";
import { generatePasswordHash } from "../../helpers/generatePasswordHash";
import superjson from "superjson";
import { createHash } from "node:crypto";
import {
  guardMutation,
  readTextLimited,
  SecurityError,
} from "../../helpers/requestSecurity";
import { takeRateLimit } from "../../helpers/uploadSecurity";

export async function handle(request: Request) {
  try {
    guardMutation(request);
    const json = superjson.parse(await readTextLimited(request, 16 * 1024));
    const { email, password, displayName } = schema.parse(json);
    const normalizedEmail = email.trim().toLowerCase();
    const normalizedDisplayName = displayName.trim();
    await takeRateLimit("auth:register:global", 100, 60);
    const emailKey = createHash("sha256").update(normalizedEmail).digest("hex");
    await takeRateLimit(`auth:register:${emailKey}`, 5, 3600);

    // Check if email already exists
    const existingUser = await db
      .selectFrom("users")
      .select("id")
      .where(sql`LOWER(email)`, "=", normalizedEmail)
      .limit(1)
      .execute();

    if (existingUser.length > 0) {
      return new Response(
        superjson.stringify({ message: "email already in use" }),
        {
          status: 409,
          headers: {
            "Content-Type": "application/json",
            "Cache-Control": "no-store",
          },
        },
      );
    }

    const passwordHash = await generatePasswordHash(password);

    // Create new user
    const newUser = await db.transaction().execute(async (trx) => {
      // Insert the user
      const [user] = await trx
        .insertInto("users")
        .values({
          email: normalizedEmail,
          displayName: normalizedDisplayName,
          role: "user", // Default role
        })
        .returning(["id", "email", "displayName", "createdAt"])
        .execute();

      // Store the password hash in another table
      await trx
        .insertInto("userPasswords")
        .values({
          userId: user.id,
          passwordHash,
        })
        .execute();

      return user;
    });

    // Create a new session
    const sessionId = randomBytes(32).toString("hex");
    const now = new Date();
    const expiresAt = new Date(now.getTime() + SessionExpirationSeconds * 1000);

    await db
      .insertInto("sessions")
      .values({
        id: sessionId,
        userId: newUser.id,
        createdAt: now,
        lastAccessed: now,
        expiresAt,
      })
      .execute();

    // Create response with user data
    const response = new Response(
      superjson.stringify({
        user: {
          ...newUser,
          role: "user" as const,
        },
      }),
      {
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "no-store",
        },
      },
    );

    // Set session cookie
    await setServerSession(response, {
      id: sessionId,
      createdAt: now.getTime(),
      lastAccessed: now.getTime(),
    });

    return response;
  } catch (error: unknown) {
    console.error(
      "Muwa registration failed",
      error instanceof Error ? error.name : "unknown",
    );
    const errorMessage =
      error instanceof SecurityError
        ? error.message
        : "Не удалось создать аккаунт. Проверьте данные и повторите позже.";
    return new Response(superjson.stringify({ message: errorMessage }), {
      status: error instanceof SecurityError ? error.status : 400,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
      },
    });
  }
}
