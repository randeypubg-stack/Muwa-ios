// adapt this to your database schema
import { db } from "../../helpers/db";
import {
  getServerSessionOrThrow,
  clearServerSession,
  NotAuthenticatedError,
} from "../../helpers/getSetServerSession";
import superjson from "superjson";
import { guardMutation, SecurityError } from "../../helpers/requestSecurity";

export async function handle(request: Request) {
  try {
    guardMutation(request);
    // Get the current session
    const session = await getServerSessionOrThrow(request);

    // Delete the session from the database
    await db.deleteFrom("sessions").where("id", "=", session.id).execute();

    // Create response with success message
    const response = new Response(
      superjson.stringify({
        success: true,
        message: "Logged out successfully",
      }),
      {
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "no-store",
        },
      },
    );

    clearServerSession(response);

    return response;
  } catch (error) {
    if (error instanceof NotAuthenticatedError) {
      const response = new Response(
        superjson.stringify({ error: "Not authenticated" }),
        {
          status: 401,
          headers: {
            "Content-Type": "application/json",
            "Cache-Control": "no-store",
          },
        },
      );
      clearServerSession(response);
      return response;
    }
    if (error instanceof SecurityError) {
      return new Response(superjson.stringify({ error: error.message }), {
        status: error.status,
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "no-store",
        },
      });
    }
    console.error(
      "Muwa logout failed",
      error instanceof Error ? error.name : "unknown",
    );
    return new Response(
      superjson.stringify({
        error: "Logout failed",
      }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "no-store",
        },
      },
    );
  }
}
