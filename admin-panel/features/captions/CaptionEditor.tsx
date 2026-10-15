import { useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Plus, X } from "lucide-react";
import { Textarea } from "../../components/Textarea";
import {
  adminValidation,
  type TrackRecord,
  type Caption,
} from "../../../backend/helpers/adminValidation";
import {
  recognitionLabel,
  minutes,
  message,
} from "../../helpers/adminPresentation";
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

export const CaptionEditor = ({
  track,
  onClose,
  onSaved,
  disabled,
}: {
  track: TrackRecord;
  onClose: () => void;
  onSaved: () => Promise<void>;
  disabled: boolean;
}) => {
  const [rows, setRows] = useState<Caption[]>(track.captions),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [time, setTime] = useState(0);
  const audio = useRef<HTMLAudioElement>(null),
    importer = useRef<HTMLInputElement>(null);
  const recognition = useQuery({
    queryKey: ["muwa-recognition", track.id],
    queryFn: () =>
      postAdminAction({ action: "get-recognition", trackId: track.id }),
    enabled: !disabled,
    retry: false,
    refetchInterval: (query) =>
      ["queued", "processing"].includes(
        query.state.data?.recognition?.status ?? "",
      )
        ? 5000
        : false,
  });
  const recognized = recognition.data?.recognition;
  const dirty = JSON.stringify(rows) !== JSON.stringify(track.captions);
  const close = () => {
    if (
      !busy &&
      (!dirty || window.confirm("Закрыть без сохранения субтитров?"))
    )
      onClose();
  };
  const update = (i: number, patch: Partial<Caption>) =>
    setRows((prev) => prev.map((r, j) => (j === i ? { ...r, ...patch } : r)));
  async function recognize() {
    setBusy(true);
    setError("");
    try {
      await postAdminAction({
        action: "recognize-track",
        trackId: track.id,
        revision: track.revision,
      });
      await recognition.refetch();
    } catch (e) {
      setError(message(e));
    } finally {
      setBusy(false);
    }
  }
  function useRecognition() {
    const doc = recognized?.document;
    if (!doc) return;
    if (!["ar", "ru", "en"].includes(doc.language)) {
      setError(
        "Этот язык сохранён в оригинальном документе. Редактор сейчас поддерживает AR, RU и EN.",
      );
      return;
    }
    if (
      dirty &&
      !window.confirm(
        "Заменить несохранённые строки результатом распознавания?",
      )
    )
      return;
    setRows(
      doc.segments.map((s) => ({
        start: s.start,
        end: s.end,
        ar: doc.language === "ar" ? s.original : "",
        ru: doc.language === "ru" ? s.original : "",
        en: doc.language === "en" ? s.original : "",
      })),
    );
    setError("");
  }
  async function save() {
    setBusy(true);
    setError("");
    try {
      const captions = adminValidation.captions.parse(rows);
      await postAdminAction({
        action: "save-captions",
        trackId: track.id,
        revision: track.revision,
        captions,
      });
      await onSaved();
    } catch (e) {
      setError(message(e));
    } finally {
      setBusy(false);
    }
  }
  async function load(file: File | undefined) {
    if (!file) return;
    try {
      if (file.size > 2 * 1024 * 1024)
        throw new Error("JSON должен быть меньше 2 МБ.");
      const value = JSON.parse(await file.text());
      setRows(
        adminValidation.captions.parse(
          Array.isArray(value) ? value : value.segments,
        ),
      );
      setError("");
    } catch (e) {
      setError(message(e));
    }
  }
  function exportRows() {
    const blob = new Blob([JSON.stringify({ segments: rows }, null, 2)], {
        type: "application/json",
      }),
      url = URL.createObjectURL(blob),
      a = document.createElement("a");
    a.href = url;
    a.download = track.id + "-captions.json";
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  return (
    <Dialog
      open
      onOpenChange={(open) => {
        if (!open) close();
      }}
    >
      <DialogContent className={`${styles.dialog} ${styles.captionDialog}`}>
        <DialogTitle>Субтитры · {track.title}</DialogTitle>
        <DialogDescription>
          Время в секундах. Строки идут по порядку, без пересечений. Нажмите
          время начала, чтобы прослушать фразу.
        </DialogDescription>
        <section className={styles.recognition} aria-live="polite">
          <div>
            <strong>
              {recognized
                ? recognitionLabel(recognized)
                : "Автоматические субтитры"}
            </strong>
            <p>
              {recognized?.status === "processing"
                ? `Распознано ${minutes(recognized.progressSeconds)} из ${minutes(track.duration)}. Загрузка и прослушивание продолжают работать.`
                : recognized?.status === "failed"
                  ? "Распознавание не завершено. Исходный файл и сохранённые субтитры не изменены; можно повторить."
                  : recognized?.status === "ready"
                    ? "Сверьте слова и время с записью. Даже уверенный результат модели может ошибаться в пении и диалектах. Черновик не виден слушателям до сохранения проверенного текста."
                    : "Сервер распознаёт оригинал локально, по одному файлу. Новые загрузки попадают в очередь автоматически."}
            </p>
            {recognized?.quality?.needsReview && (
              <p>
                Есть неуверенно распознанные фразы или язык. Проверьте текст
                перед сохранением.
              </p>
            )}
            {recognized?.errorCode && (
              <p>
                Причина: {recognized.errorCode}. Результат можно повторить
                кнопкой ниже.
              </p>
            )}
            {recognized?.status === "processing" && (
              <progress
                aria-label="Распознавание оригинала"
                max={track.duration}
                value={Math.min(track.duration, recognized.progressSeconds)}
              />
            )}
            {recognition.data?.trackRevision !== undefined &&
              recognition.data.trackRevision !== track.revision && (
                <p className={styles.warning}>
                  Запись обновилась после открытия редактора. Закройте его и
                  откройте заново, чтобы сохранить текст без конфликта с новыми
                  изменениями.
                </p>
              )}
            {recognition.error && <p>{message(recognition.error)}</p>}
          </div>
          <div>
            <Button
              size="sm"
              variant="outline"
              disabled={
                busy ||
                disabled ||
                ["queued", "processing"].includes(recognized?.status ?? "")
              }
              onClick={() => void recognize()}
            >
              {recognized ? "Распознать заново" : "Распознать оригинал"}
            </Button>
            {recognized?.document && (
              <Button
                size="sm"
                variant="outline"
                disabled={busy || disabled}
                onClick={useRecognition}
              >
                Взять распознанный текст
              </Button>
            )}
          </div>
        </section>
        {track.audioUrl && (
          <audio
            ref={audio}
            src={track.audioUrl}
            controls
            preload="metadata"
            onTimeUpdate={() => setTime(audio.current?.currentTime ?? 0)}
            className={styles.audio}
          />
        )}
        <div className={styles.captionToolbar}>
          <span>
            {minutes(time)} / {minutes(track.duration)} · {rows.length} строк
          </span>
          <Button
            size="sm"
            variant="outline"
            disabled={busy}
            onClick={() => importer.current?.click()}
          >
            Импорт JSON
          </Button>
          <Button size="sm" variant="ghost" onClick={exportRows}>
            Экспорт
          </Button>
          <Input
            ref={importer}
            className={styles.hidden}
            type="file"
            accept="application/json,.json"
            onChange={(e) => void load(e.target.files?.[0])}
          />
        </div>
        <div className={styles.captionRows}>
          {rows.map((r, i) => (
            <div
              key={i}
              className={`${styles.captionRow} ${time >= r.start && time < r.end ? styles.captionActive : ""}`}
            >
              <div className={styles.timing}>
                <Button
                  size="sm"
                  variant="ghost"
                  aria-label={`Перейти к строке ${i + 1}`}
                  onClick={() => {
                    if (audio.current) audio.current.currentTime = r.start;
                  }}
                >
                  {String(i + 1).padStart(2, "0")}
                </Button>
                <label>
                  Начало
                  <Input
                    type="number"
                    min={0}
                    step="0.1"
                    value={r.start}
                    disabled={busy}
                    onChange={(e) =>
                      update(i, { start: Number(e.target.value) })
                    }
                  />
                </label>
                <label>
                  Конец
                  <Input
                    type="number"
                    min={0}
                    step="0.1"
                    value={r.end}
                    disabled={busy}
                    onChange={(e) => update(i, { end: Number(e.target.value) })}
                  />
                </label>
                <Button
                  variant="ghost"
                  size="icon-sm"
                  disabled={busy}
                  aria-label={`Удалить строку ${i + 1}`}
                  onClick={() =>
                    setRows((prev) => prev.filter((_, j) => j !== i))
                  }
                >
                  <X size={15} />
                </Button>
              </div>
              <label>
                Оригинал (AR)
                <Textarea
                  dir="rtl"
                  value={r.ar}
                  disabled={busy}
                  onChange={(e) => update(i, { ar: e.target.value })}
                />
              </label>
              <label>
                Русский
                <Textarea
                  value={r.ru}
                  disabled={busy}
                  onChange={(e) => update(i, { ru: e.target.value })}
                />
              </label>
              <label>
                English
                <Textarea
                  value={r.en}
                  disabled={busy}
                  onChange={(e) => update(i, { en: e.target.value })}
                />
              </label>
            </div>
          ))}
        </div>
        <Button
          variant="outline"
          disabled={busy || rows.length >= 600}
          onClick={() =>
            setRows((prev) => [
              ...prev,
              {
                start: prev.at(-1)?.end ?? 0,
                end: Math.min(track.duration, (prev.at(-1)?.end ?? 0) + 3),
                ar: "",
                ru: "",
                en: "",
              },
            ])
          }
        >
          <Plus size={16} />
          Добавить строку
        </Button>
        {error && (
          <p role="alert" className={styles.error}>
            {error}
          </p>
        )}
        <div className={styles.dialogActions}>
          <Button variant="outline" disabled={busy} onClick={close}>
            Отмена
          </Button>
          <Button disabled={busy || disabled} onClick={() => void save()}>
            {busy ? "Сохраняем…" : "Сохранить проверенный текст"}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
};
