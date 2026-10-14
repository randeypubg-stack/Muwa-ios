import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Textarea } from "../../components/Textarea";
import {
  adminValidation,
  type SubmissionRecord,
} from "../../../backend/helpers/adminValidation";
import { message } from "../../helpers/adminPresentation";
import { put } from "../../helpers/mediaUpload";
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

export const SubmissionReview = ({
  submission: s,
  onClose,
  onSaved,
  disabled,
}: {
  submission: SubmissionRecord;
  onClose: () => void;
  onSaved: () => Promise<void>;
  disabled: boolean;
}) => {
  const [title, setTitle] = useState(s.title),
    [artist, setArtist] = useState(s.artist),
    [duration, setDuration] = useState(0),
    [reason, setReason] = useState(""),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [phase, setPhase] = useState("");
  const source = useQuery({
    queryKey: ["muwa-admin", "submission", s.id],
    queryFn: () =>
      postAdminAction({ action: "open-submission", submissionId: s.id }),
    retry: false,
    enabled: !disabled,
  });
  async function approve() {
    setBusy(true);
    setError("");
    try {
      const meta = { title, artist, language: s.language, duration };
      adminValidation.action.parse({
        action: "approve-submission",
        submissionId: s.id,
        revision: s.revision,
        uploadId: "00000000-0000-4000-8000-000000000000",
        ...meta,
      });
      setPhase("Готовим публикацию…");
      const plan = await postAdminAction({
        action: "prepare-approval",
        submissionId: s.id,
        revision: s.revision,
      });
      for (const f of plan.files ?? []) {
        setPhase(
          f.part === "audio" ? "Переносим аудио…" : "Переносим обложку…",
        );
        const r = await fetch(f.sourceUrl!);
        if (!r.ok) throw new Error("Файл публикации недоступен.");
        await put(f.presignedUrl, f.headers, await r.blob());
      }
      setPhase("Публикуем…");
      await postAdminAction({
        action: "approve-submission",
        submissionId: s.id,
        revision: s.revision,
        uploadId: plan.uploadId!,
        ...meta,
      });
      await onSaved();
    } catch (e) {
      setError(message(e));
    } finally {
      setBusy(false);
      setPhase("");
    }
  }
  async function reject() {
    setBusy(true);
    setError("");
    try {
      await postAdminAction({
        action: "reject-submission",
        submissionId: s.id,
        revision: s.revision,
        reason,
      });
      await onSaved();
    } catch (e) {
      setError(message(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <Dialog
      open
      onOpenChange={(open) => {
        if (!open && !busy) onClose();
      }}
    >
      <DialogContent className={styles.dialog}>
        <DialogTitle>Проверка публикации</DialogTitle>
        <DialogDescription>
          Материал станет доступен в каталоге только после вашего одобрения.
        </DialogDescription>
        <label>
          Название
          <Input
            value={title}
            disabled={busy}
            onChange={(e) => setTitle(e.target.value)}
          />
        </label>
        <label>
          Исполнитель
          <Input
            value={artist}
            disabled={busy}
            onChange={(e) => setArtist(e.target.value)}
          />
        </label>
        {source.data?.artworkUrl && (
          <img
            src={source.data.artworkUrl}
            alt="Обложка публикации"
            className={styles.reviewCover}
          />
        )}{" "}
        {source.isPending ? (
          <p>Подготавливаем предпросмотр…</p>
        ) : source.error ? (
          <p role="alert" className={styles.error}>
            {message(source.error)}
          </p>
        ) : (
          <audio
            src={source.data?.audioUrl}
            controls
            preload="metadata"
            onLoadedMetadata={(e) =>
              setDuration(
                Number.isFinite(e.currentTarget.duration)
                  ? e.currentTarget.duration
                  : 0,
              )
            }
            className={styles.audio}
          />
        )}
        <label>
          Причина отклонения
          <Textarea
            value={reason}
            disabled={busy}
            onChange={(e) => setReason(e.target.value)}
            placeholder="Коротко объясните решение"
            maxLength={1000}
          />
        </label>
        {error && (
          <p role="alert" className={styles.error}>
            {error}
          </p>
        )}
        <div className={styles.dialogActions}>
          <Button
            variant="outline"
            disabled={busy || disabled || reason.trim().length < 3}
            onClick={() => void reject()}
          >
            Отклонить
          </Button>
          <Button
            disabled={busy || disabled || duration <= 0}
            onClick={() => void approve()}
          >
            {busy ? phase || "Сохраняем…" : "Одобрить и опубликовать"}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
};
