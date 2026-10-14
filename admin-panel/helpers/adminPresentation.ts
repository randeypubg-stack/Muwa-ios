import type { TrackRecord } from "../../backend/helpers/adminValidation";

export const logo = "/assets/app-mark.png";
export const labels: Record<string, string> = {
  published: "Опубликован",
  draft: "Черновик",
  archived: "В архиве",
  pending: "На проверке",
  rejected: "Отклонён",
  uploading: "Загружается",
};
const recognitionLabels: Record<string, string> = {
  queued: "Субтитры в очереди",
  processing: "Распознаём субтитры",
  ready: "Оригинал распознан",
  failed: "Ошибка распознавания",
};
export const recognitionLabel = (job: TrackRecord["recognition"]) =>
  job?.status === "ready"
    ? "Черновик текста · сверить с записью"
    : job
      ? recognitionLabels[job.status]
      : "Ожидает распознавания";
export const eventLabels: Record<string, string> = {
  "track.created": "Добавлен нашид",
  "track.updated": "Изменён нашид",
  "track.published": "Нашид опубликован",
  "track.draft": "Возвращён в черновики",
  "track.archived": "Нашид снят с публикации",
  "captions.updated": "Обновлены субтитры",
  "recognition.queued": "Запущено распознавание оригинала",
  "submission.received": "Поступила публикация",
  "submission.rejected": "Публикация отклонена",
  "submission.published": "Публикация одобрена",
  "telegram.imported": "Нашид импортирован из Telegram",
  "telegram.linked": "Повтор из Telegram связан с существующим нашидом",
};
export const minutes = (n: number) =>
  `${Math.floor(n / 60)}:${String(Math.floor(n % 60)).padStart(2, "0")}`;
export const date = (s: string) =>
  new Date(s).toLocaleString("ru-RU", {
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
export const message = (e: unknown) =>
  e instanceof Error ? e.message : "Не удалось выполнить действие.";
