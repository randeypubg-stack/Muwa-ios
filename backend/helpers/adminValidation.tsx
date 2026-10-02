import { z } from "zod";
const id = z.string().regex(/^[A-Za-z0-9_-]{1,80}$/);
const revision = z.number().int().positive();
const status = z.enum(["draft", "published", "archived"]);
const caption = z.object({
  start: z.number().finite().nonnegative(),
  end: z.number().finite().positive(),
  ar: z.string().max(2000).default(""),
  ru: z.string().max(2000).default(""),
  en: z.string().max(2000).default(""),
});
const captions = z
  .array(caption)
  .max(600)
  .superRefine((rows, ctx) => {
    rows.forEach((row, i) => {
      if (
        row.end <= row.start ||
        (i > 0 && row.start < rows[i - 1].end) ||
        ![row.ar, row.ru, row.en].some((t) => t.trim())
      )
        ctx.addIssue({
          code: "custom",
          path: [i],
          message:
            "Строки должны идти по времени, без пересечений и пустого текста.",
        });
    });
  });
const file = z
  .object({
    part: z.enum(["audio", "cover"]),
    contentType: z.enum([
      "audio/mpeg",
      "audio/mp4",
      "audio/x-m4a",
      "audio/wav",
      "image/jpeg",
      "image/png",
      "image/webp",
    ]),
    sizeBytes: z
      .number()
      .int()
      .positive()
      .max(100 * 1024 * 1024),
  })
  .superRefine((f, ctx) => {
    if (!f.contentType.startsWith(f.part === "audio" ? "audio/" : "image/"))
      ctx.addIssue({
        code: "custom",
        message: "Тип файла не соответствует назначению.",
      });
    if (f.part === "cover" && f.sizeBytes > 10 * 1024 * 1024)
      ctx.addIssue({
        code: "custom",
        message: "Обложка должна быть меньше 10 МБ.",
      });
  });
const metadata = {
  title: z.string().trim().min(1).max(180),
  artist: z.string().trim().min(1).max(180),
  language: z.string().trim().min(2).max(10),
  duration: z.number().finite().positive().max(86400),
};
const action = z.discriminatedUnion("action", [
  z.object({ action: z.literal("cleanup-uploads") }),
  z.object({
    action: z.literal("prepare-upload"),
    trackId: id.optional(),
    revision: revision.optional(),
    files: z.array(file).min(1).max(2),
  }),
  z.object({
    action: z.literal("save-track"),
    trackId: id.optional(),
    revision: revision.optional(),
    uploadId: z.string().uuid().optional(),
    ...metadata,
    status,
  }),
  z.object({ action: z.literal("set-status"), trackId: id, revision, status }),
  z.object({
    action: z.literal("save-captions"),
    trackId: id,
    revision,
    captions,
  }),
  z.object({
    action: z.literal("refresh-submissions"),
    cursor: z
      .object({
        token: z.string().max(4096).optional(),
        offset: z.number().int().min(0).max(1000),
      })
      .optional(),
  }),
  z.object({
    action: z.literal("open-submission"),
    submissionId: z.string().uuid(),
  }),
  z.object({
    action: z.literal("prepare-approval"),
    submissionId: z.string().uuid(),
    revision,
  }),
  z.object({
    action: z.literal("approve-submission"),
    submissionId: z.string().uuid(),
    revision,
    uploadId: z.string().uuid(),
    ...metadata,
  }),
  z.object({
    action: z.literal("reject-submission"),
    submissionId: z.string().uuid(),
    revision,
    reason: z.string().trim().min(3).max(1000),
  }),
]);
const query = z.object({
  section: z
    .enum(["catalog", "submissions", "history", "errors"])
    .default("catalog"),
  search: z.string().max(100).default(""),
  status: z
    .enum([
      "all",
      "draft",
      "published",
      "archived",
      "pending",
      "rejected",
      "uploading",
    ])
    .default("all"),
  page: z.coerce.number().int().min(1).max(500).default(1),
});
export type AdminAction = z.infer<typeof action>;
export type Caption = z.infer<typeof caption>;
export type AdminQuery = z.infer<typeof query>;
export type TrackRecord = {
  id: string;
  title: string;
  artist: string;
  language: string;
  duration: number;
  audioUrl: string | null;
  artworkUrl: string | null;
  status: string;
  revision: number;
  captionsRevision: number;
  captions: Caption[];
  updatedAt: string;
};
export type SubmissionRecord = {
  id: string;
  title: string;
  artist: string;
  language: string;
  status: string;
  revision: number;
  userId: number | null;
  rejectionReason: string | null;
  updatedAt: string;
};
export type AuditRecord = {
  id: string;
  action: string;
  entityId: string;
  actor: string | null;
  createdAt: string;
};
export type AdminState = {
  tracks: TrackRecord[];
  submissions: SubmissionRecord[];
  events: AuditRecord[];
  errors?: {
    id: string;
    platform: string;
    version: string;
    build: string;
    area: string;
    errorType: string;
    errorCode: number;
    occurredAt: string;
  }[];
  total: number;
  page: number;
  stats: { published: number; drafts: number; pending: number };
  recognition: { enabled: false; message: string };
};
export type UploadFile = {
  part: "audio" | "cover";
  filename: string;
  url: string;
  contentType: string;
  sizeBytes: number;
  presignedUrl: string;
  headers: Record<string, string>;
  sourceUrl?: string;
  visibility?: "private" | "public";
  sourceSha256?: string;
};
export type AdminResult = {
  ok: true;
  trackId?: string;
  uploadId?: string;
  files?: UploadFile[];
  audioUrl?: string;
  artworkUrl?: string;
  refreshed?: number;
  removed?: number;
  nextCursor?: { token?: string; offset: number };
};
export const adminValidation = { action, query, captions, id };
