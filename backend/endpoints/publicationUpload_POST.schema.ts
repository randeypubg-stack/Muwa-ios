import { z } from "zod";
import superjson from "superjson";
export const schema = z
  .object({
    draftId: z.string().uuid(),
    part: z.enum(["audio", "cover", "submission"]),
    originalName: z.string().min(1).max(180),
    contentType: z.enum([
      "audio/mpeg",
      "audio/mp4",
      "audio/x-m4a",
      "audio/wav",
      "image/jpeg",
      "image/png",
      "image/webp",
      "application/json",
    ]),
    sizeBytes: z
      .number()
      .int()
      .positive()
      .max(100 * 1024 * 1024),
    sha256: z
      .string()
      .regex(/^[a-f0-9]{64}$/)
      .optional(),
  })
  .superRefine((value, ctx) => {
    const valid =
      value.part === "audio"
        ? value.contentType.startsWith("audio/")
        : value.part === "cover"
          ? value.contentType.startsWith("image/") &&
            value.sizeBytes <= 10 * 1024 * 1024
          : value.contentType === "application/json" &&
            value.sizeBytes <= 256 * 1024;
    if (!valid)
      ctx.addIssue({
        code: "custom",
        message: "Неверный формат или размер файла.",
      });
  });
export type InputType = z.infer<typeof schema>;
export type OutputType = {
  storageKey: string;
  presignedUrl: string;
  headers?: Record<string, string>;
  alreadyUploaded?: boolean;
};
export async function postPublicationUpload(
  input: InputType,
  init?: RequestInit,
): Promise<OutputType> {
  const response = await fetch("/_api/publicationUpload", {
    ...init,
    method: "POST",
    credentials: "same-origin",
    headers: { ...init?.headers, "Content-Type": "application/json" },
    body: superjson.stringify(schema.parse(input)),
  });
  const value = superjson.parse<OutputType & { error?: string }>(
    await response.text(),
  );
  if (!response.ok)
    throw new Error(value.error ?? "Не удалось подготовить загрузку.");
  return value;
}
