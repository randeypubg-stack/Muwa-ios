import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Upload } from "lucide-react";
import { Choice } from "../../components/Choice";
import {
  adminValidation,
  type TrackRecord,
  type AdminAction,
} from "../../../backend/helpers/adminValidation";
import { labels, message } from "../../helpers/adminPresentation";
import { mime, audioDuration, put } from "../../helpers/mediaUpload";
import { Button } from "../../components/Button";
import { Input } from "../../components/Input";
import {
  Dialog,
  DialogContent,
  DialogTitle,
  DialogDescription,
} from "../../components/Dialog";
import { postAdminAction } from "../../../backend/endpoints/admin/action_POST.schema";
import styles from "../../components/AdminWorkspace.module.css";

export const TrackEditor = ({
  track,
  onClose,
  onSaved,
  disabled,
}: {
  track: TrackRecord | null;
  onClose: () => void;
  onSaved: () => Promise<void>;
  disabled: boolean;
}) => {
  const [title, setTitle] = useState(track?.title ?? ""),
    [artist, setArtist] = useState(track?.artist ?? ""),
    [language, setLanguage] = useState(track?.language ?? "ar"),
    [status, setStatus] = useState(track?.status ?? "draft");
  const [audio, setAudio] = useState<File | null>(null),
    [cover, setCover] = useState<File | null>(null),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [phase, setPhase] = useState("");
  const recognition = useQuery({
    queryKey: ["muwa-recognition", track?.id],
    queryFn: () =>
      postAdminAction({ action: "get-recognition", trackId: track!.id }),
    enabled: !!track && !disabled,
    retry: false,
    refetchInterval: (query) =>
      ["queued", "processing"].includes(
        query.state.data?.recognition?.status ?? "",
      )
        ? 5000
        : false,
  });
  const suggestion = recognition.data?.titleSuggestion;
  const dirty =
    title !== (track?.title ?? "") ||
    artist !== (track?.artist ?? "") ||
    language !== (track?.language ?? "ar") ||
    status !== (track?.status ?? "draft") ||
    !!audio ||
    !!cover;
  const close = () => {
    if (
      !busy &&
      (!dirty || window.confirm("Закрыть без сохранения изменений?"))
    )
      onClose();
  };
  async function save() {
    setBusy(true);
    setError("");
    try {
      const duration = audio
        ? await audioDuration(audio)
        : (track?.duration ?? 0);
      const input = adminValidation.action.parse({
        action: "save-track",
        trackId: track?.id,
        revision: track?.revision,
        title,
        artist,
        language,
        duration,
        status,
      });
      const selected = [
        ...(audio ? [{ part: "audio" as const, file: audio }] : []),
        ...(cover ? [{ part: "cover" as const, file: cover }] : []),
      ];
      let uploadId: string | undefined;
      if (selected.length) {
        setPhase("Готовим загрузку…");
        const plan = await postAdminAction({
          action: "prepare-upload",
          trackId: track?.id,
          revision: track?.revision,
          files: selected.map((s) => ({
            part: s.part,
            contentType: mime(s.file) as "audio/mpeg",
            sizeBytes: s.file.size,
          })),
        });
        uploadId = plan.uploadId;
        for (const f of plan.files ?? []) {
          setPhase(
            f.part === "audio" ? "Загружаем аудио…" : "Загружаем обложку…",
          );
          await put(
            f.presignedUrl,
            f.headers,
            selected.find((s) => s.part === f.part)!.file,
          );
        }
      }
      setPhase("Сохраняем…");
      await postAdminAction({ ...input, uploadId } as AdminAction);
      await onSaved();
    } catch (e) {
      setError(message(e));
    } finally {
      setBusy(false);
      setPhase("");
    }
  }
  return (
    <Dialog
      open
      onOpenChange={(open) => {
        if (!open) close();
      }}
    >
      <DialogContent
        className={styles.dialog}
        onEscapeKeyDown={(e) => {
          if (busy) e.preventDefault();
        }}
        onPointerDownOutside={(e) => {
          if (busy) e.preventDefault();
        }}
      >
        <DialogTitle>
          {track ? "Редактировать нашид" : "Добавить нашид"}
        </DialogTitle>
        <DialogDescription>
          Аудио до 100 МБ. Обложка до 10 МБ. Черновик виден только
          администраторам.
        </DialogDescription>
        <div className={styles.editorGrid}>
          <label>
            Название
            <Input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              dir="auto"
              maxLength={180}
              disabled={busy}
            />
          </label>
          <label>
            Исполнитель
            <Input
              value={artist}
              onChange={(e) => setArtist(e.target.value)}
              maxLength={180}
              disabled={busy}
            />
          </label>
          <label>
            Язык оригинала
            <Input
              value={language}
              onChange={(e) => setLanguage(e.target.value)}
              maxLength={10}
              disabled={busy}
            />
          </label>
          <label>
            Статус
            <Choice
              label="Статус нашида"
              value={status}
              onChange={setStatus}
              options={["draft", "published", "archived"].map((s) => [
                s,
                labels[s],
              ])}
            />
          </label>
        </div>
        {suggestion && !audio && (
          <section
            className={styles.recognition}
            aria-label="Предложение названия"
          >
            <div>
              <strong>
                Название из{" "}
                {suggestion.method === "refrain"
                  ? "повторяющейся фразы"
                  : "первых слов"}
              </strong>
              <p dir="auto">{suggestion.title}</p>
              <p>
                Это предложение по записи, а не установленное название.{" "}
                {suggestion.needsReview
                  ? "Распознавание требует проверки по аудио. "
                  : ""}
                Изменение сохранится только после нажатия «Сохранить».
              </p>
            </div>
            <Button
              variant="outline"
              size="sm"
              disabled={busy}
              onClick={() => setTitle(suggestion.title)}
            >
              Подставить название
            </Button>
          </section>
        )}
        {recognition.error && (
          <p className={styles.error} role="alert">
            {message(recognition.error)}
          </p>
        )}
        <label className={styles.filePicker}>
          <Upload size={20} />
          <strong>
            {audio?.name ?? (track ? "Заменить аудио" : "Выбрать аудио")}
          </strong>
          <span>MP3, M4A или WAV</span>
          <Input
            type="file"
            accept="audio/mpeg,audio/mp4,audio/x-m4a,audio/wav,.mp3,.m4a,.wav"
            disabled={busy}
            onChange={(e) => setAudio(e.target.files?.[0] ?? null)}
          />
        </label>
        <label className={styles.filePicker}>
          <strong>{cover?.name ?? "Выбрать обложку"}</strong>
          <span>JPG, PNG или WebP · необязательно</span>
          <Input
            type="file"
            accept="image/jpeg,image/png,image/webp"
            disabled={busy}
            onChange={(e) => setCover(e.target.files?.[0] ?? null)}
          />
        </label>
        {track?.audioUrl && !audio && (
          <audio
            controls
            preload="none"
            src={track.audioUrl}
            className={styles.audio}
          />
        )}
        {audio && track && (
          <p className={styles.warning}>
            Замена аудио сбросит субтитры: старые тайминги могут не совпадать.
          </p>
        )}
        {error && (
          <p className={styles.error} role="alert">
            {error}
          </p>
        )}
        <div className={styles.dialogActions}>
          <Button variant="outline" disabled={busy} onClick={close}>
            Отмена
          </Button>
          <Button
            disabled={busy || disabled || (!track && !audio)}
            onClick={() => void save()}
          >
            {busy ? phase || "Сохраняем…" : "Сохранить"}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
};
