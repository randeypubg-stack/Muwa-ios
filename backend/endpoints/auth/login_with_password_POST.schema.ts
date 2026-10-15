import { z } from "zod";
import { User } from "../../helpers/User";
import superjson from "superjson";

export const schema = z.object({
  email: z.string().max(254).email("Email is required"),
  // bcrypt ignores bytes after 72; reject them before comparing a credential.
  password: z.string().min(1, "Password is required").max(72).refine(
    value => new TextEncoder().encode(value).length <= 72,
    "Password exceeds the supported byte length",
  ),
});

export type OutputType = {
  user: User;
};

export const postLogin = async (
  body: z.infer<typeof schema>,
  init?: RequestInit,
): Promise<OutputType> => {
  const validatedInput = schema.parse(body);
  const result = await fetch(`/_api/auth/login_with_password`, {
    method: "POST",
    body: superjson.stringify(validatedInput),
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
    credentials: "include", // Important for cookies to be sent and received
  });

  if (!result.ok) {
    const errorData = superjson.parse<{ message: string }>(await result.text());
    throw new Error(errorData.message || "Login failed");
  }

  return superjson.parse<OutputType>(await result.text());
};
