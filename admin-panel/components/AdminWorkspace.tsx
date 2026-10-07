import { useEffect, useRef, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Library,
  Upload,
  Inbox,
  History,
  Activity,
  LogOut,
  RefreshCw,
  Search,
  Plus,
  FileText,
  ArrowUpRight,
  Check,
  Archive,
  ChevronLeft,
  ChevronRight,
  X,
} from "lucide-react";
import { Button } from "./Button";
import { Input } from "./Input";
import { Textarea } from "./Textarea";
import {
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
} from "./Select";
import {
  Dialog,
  DialogContent,
  DialogTitle,
  DialogDescription,
} from "./Dialog";
import { PasswordLoginForm } from "./PasswordLoginForm";
import { useAuth } from "../helpers/useAuth";
import { getAdminState } from "../../backend/endpoints/admin/state_GET.schema";
import { postAdminAction } from "../../backend/endpoints/admin/action_POST.schema";
import {
  adminValidation,
  type AdminState,
  type AdminQuery,
  type TrackRecord,
  type Caption,
  type SubmissionRecord,
  type AdminAction,
} from "../../backend/helpers/adminValidation";
import styles from "./AdminWorkspace.module.css";
const logo = "/assets/app-mark.png";
const labels: Record<string, string> = {
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
const eventLabels: Record<string, string> = {
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
const minutes = (n: number) =>
  `${Math.floor(n / 60)}:${String(Math.floor(n % 60)).padStart(2, "0")}`;
const date = (s: string) =>
  new Date(s).toLocaleString("ru-RU", {
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
const message = (e: unknown) =>
  e instanceof Error ? e.message : "Не удалось выполнить действие.";
function mime(file: File) {
  return (
    file.type ||
    (
      {
        mp3: "audio/mpeg",
        m4a: "audio/mp4",
        wav: "audio/wav",
        jpg: "image/jpeg",
        jpeg: "image/jpeg",
        png: "image/png",
        webp: "image/webp",
      } as Record<string, string>
    )[file.name.split(".").pop()?.toLowerCase() ?? ""] ||
    ""
  );
}
async function audioDuration(file: Blob) {
  return new Promise<number>((resolve, reject) => {
    const url = URL.createObjectURL(file),
      audio = new Audio();
    const done = () => {
      clearTimeout(timer);
      audio.removeAttribute("src");
      audio.load();
      URL.revokeObjectURL(url);
    };
    const timer = setTimeout(() => {
      done();
      reject(new Error("Не удалось определить длительность аудио."));
    }, 15000);
    audio.preload = "metadata";
    audio.onloadedmetadata = () => {
      const duration = audio.duration;
      done();
      if (Number.isFinite(duration) && duration > 0) resolve(duration);
      else reject(new Error("Проверьте формат аудио."));
    };
    audio.onerror = () => {
      done();
      reject(new Error("Этот аудиофайл не читается."));
    };
    audio.src = url;
  });
}
async function put(url: string, headers: Record<string, string>, file: Blob) {
  const r = await fetch(url, { method: "PUT", headers, body: file });
  if (!r.ok)
    throw new Error("Файл не загрузился. Проверьте соединение и повторите.");
}
function Choice({
  value,
  onChange,
  options,
  label,
}: {
  value: string;
  onChange: (s: string) => void;
  options: [string, string][];
  label: string;
}) {
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger aria-label={label}>
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {options.map(([v, l]) => (
          <SelectItem key={v} value={v}>
            {l}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
export const AdminWorkspace = () => {
  const { authState, logout } = useAuth();
  // Defense in depth while the hosting-level frame-ancestors header is configured.
  // Do not render login or authenticated controls inside any iframe.
  if (typeof window !== "undefined" && window.self !== window.top)
    return (
      <main className={styles.gate}>
        <p>Откройте панель Muwa в отдельном окне.</p>
        <a href="/admin" target="_blank" rel="noopener noreferrer">
          Открыть панель
        </a>
      </main>
    );
  if (authState.type === "loading")
    return (
      <main className={styles.gate} aria-busy="true">
        <img src={logo} alt="Muwa" />
        <p>Проверяем доступ…</p>
      </main>
    );
  if (authState.type === "unauthenticated")
    return (
      <main className={styles.gate}>
        <div className={styles.login}>
          <img src={logo} alt="Muwa" />
          <span className={styles.eyebrow}>MUWA / УПРАВЛЕНИЕ</span>
          <h1>
            Ваш каталог.
            <br />
            Под вашим контролем.
          </h1>
          <p>Войдите в аккаунт администратора Muwa.</p>
          <PasswordLoginForm redirectTo="/admin" />
          <a href="/">
            Вернуться к Muwa <ArrowUpRight size={14} />
          </a>
        </div>
        <div className={styles.gateArt}>
          <img src={logo} alt="" />
          <p>
            Нашиды без музыки.
            <br />
            <span>Пространство для вашей коллекции.</span>
          </p>
        </div>
      </main>
    );
  if (authState.user.role !== "admin")
    return (
      <main className={styles.gate}>
        <div className={styles.login}>
          <img src={logo} alt="Muwa" />
          <h1>Нет доступа к панели</h1>
          <p>Для {authState.user.email} не назначены права администратора.</p>
          <Button onClick={() => void logout()}>Выйти и сменить аккаунт</Button>
        </div>
      </main>
    );
  return (
    <AdminConsole
      userName={authState.user.displayName || authState.user.email}
      onLogout={() => logout()}
    />
  );
};
// The same component is used by dev-only examples; production data always comes from the guarded API.
export const AdminConsole = ({
  userName,
  onLogout,
  exampleState,
}: {
  userName: string;
  onLogout: () => Promise<void>;
  exampleState?: AdminState;
}) => {
  const client = useQueryClient();
  const [section, setSection] = useState<AdminQuery["section"]>("catalog"),
    [search, setSearch] = useState(""),
    [querySearch, setQuerySearch] = useState(""),
    [status, setStatus] = useState("all"),
    [page, setPage] = useState(1);
  const [editor, setEditor] = useState<TrackRecord | null | undefined>(
      undefined,
    ),
    [captionTrack, setCaptionTrack] = useState<TrackRecord | null>(null),
    [review, setReview] = useState<SubmissionRecord | null>(null);
  const [error, setError] = useState(""),
    [notice, setNotice] = useState(""),
    [busy, setBusy] = useState(false);
  useEffect(() => {
    const timer = setTimeout(() => {
      setQuerySearch(search);
      setPage(1);
    }, 350);
    return () => clearTimeout(timer);
  }, [search]);
  const query = useQuery({
    queryKey: ["muwa-admin", section, querySearch, status, page],
    queryFn: ({ signal }) =>
      getAdminState(
        {
          section,
          search: querySearch,
          status: status as AdminQuery["status"],
          page,
        },
        { signal },
      ),
    enabled: !exampleState,
    retry: false,
    staleTime: 15000,
    refetchInterval: 15000,
  });
  const data = exampleState ?? query.data;
  async function refresh() {
    if (exampleState) return;
    await client.invalidateQueries({ queryKey: ["muwa-admin"] });
  }
  async function run(action: AdminAction, success: string) {
    setBusy(true);
    setError("");
    setNotice("");
    try {
      if (exampleState)
        throw new Error(
          "Это пример интерфейса. Для изменений откройте /admin.",
        );
      let result = await postAdminAction(action);
      if (action.action === "refresh-submissions") {
        while (result.nextCursor)
          result = await postAdminAction({
            action: "refresh-submissions",
            cursor: result.nextCursor,
          });
      }
      setNotice(success);
      await refresh();
      return result;
    } catch (e) {
      setError(message(e));
      throw e;
    } finally {
      setBusy(false);
    }
  }
  function navigate(s: AdminQuery["section"]) {
    setSection(s);
    setPage(1);
    setStatus("all");
    setSearch("");
  }
  return (
    <div className={styles.workspace}>
      <aside className={styles.sidebar}>
        <a href="/admin" className={styles.brand}>
          <img src={logo} alt="" />
          <span>
            Muwa<small>ПАНЕЛЬ УПРАВЛЕНИЯ</small>
          </span>
        </a>
        <div className={styles.navLabel}>КОЛЛЕКЦИЯ</div>
        <nav aria-label="Разделы панели">
          {(
            [
              ["catalog", Library, "Каталог"],
              ["submissions", Inbox, "Публикации"],
              ["history", History, "Журнал"],
              ["errors", Activity, "Ошибки приложения"],
            ] as const
          ).map(([id, Icon, title]) => (
            <Button
              key={id}
              variant="ghost"
              className={`${styles.navItem} ${section === id ? styles.active : ""}`}
              onClick={() => navigate(id)}
              aria-current={section === id ? "page" : undefined}
            >
              <Icon size={18} />
              <span>{title}</span>
              {id === "submissions" && !!data?.stats.pending && (
                <b>{data.stats.pending}</b>
              )}
            </Button>
          ))}
        </nav>
        <div className={styles.sidebarBottom}>
          <div className={styles.server}>
            <i />
            Сервер Muwa<small>Существующая база и аккаунты</small>
          </div>
          <div className={styles.account}>
            <span className={styles.avatar}>
              {userName.charAt(0).toUpperCase()}
            </span>
            <span>
              {userName}
              <small>Администратор</small>
            </span>
            <Button
              variant="ghost"
              size="icon"
              aria-label="Выйти"
              onClick={() => {
                void onLogout().catch((e) => setError(message(e)));
              }}
            >
              <LogOut size={16} />
            </Button>
          </div>
        </div>
      </aside>
      <main className={styles.main}>
        <header className={styles.topbar}>
          <span>
            Muwa <span className={styles.slash}>/</span> Управление
          </span>
          <a href="/" target="_blank" rel="noreferrer">
            Открыть Muwa <ArrowUpRight size={14} />
          </a>
        </header>
        <div className={styles.content}>
          <div className={styles.heading}>
            <div>
              <span className={styles.eyebrow}>ВАША КОЛЛЕКЦИЯ</span>
              <h1>
                {section === "catalog"
                  ? "Каталог нашидов"
                  : section === "submissions"
                    ? "Публикации"
                    : section === "errors"
                      ? "Ошибки приложения"
                      : "Журнал действий"}
              </h1>
              <p>
                {section === "catalog"
                  ? "Загружайте, редактируйте и публикуйте нашиды."
                  : section === "submissions"
                    ? "Прослушайте и проверьте материалы перед публикацией."
                    : section === "errors"
                      ? "Обезличенные категории ошибок за 14 дней. Отправка включается в приложении."
                      : "История изменений каталога и решений модерации."}
              </p>
            </div>
            <div className={styles.headingActions}>
              <Button
                variant="outline"
                disabled={busy || query.isFetching}
                onClick={() => {
                  if (section === "submissions")
                    void run(
                      { action: "refresh-submissions" },
                      "Публикации синхронизированы.",
                    ).catch(() => {});
                  else void refresh();
                }}
              >
                <RefreshCw size={16} />
                Обновить
              </Button>
              {section === "submissions" && (
                <Button
                  variant="outline"
                  disabled={busy}
                  onClick={() => {
                    if (
                      window.confirm(
                        "Удалить незавершённые загрузки старше 48 часов? Материалы на проверке и опубликованные нашиды сохранятся.",
                      )
                    )
                      void run(
                        { action: "cleanup-uploads" },
                        "Просроченные загрузки очищены.",
                      ).catch(() => {});
                  }}
                >
                  Очистить незавершённые загрузки
                </Button>
              )}
              {section === "catalog" && (
                <Button disabled={busy} onClick={() => setEditor(null)}>
                  <Plus size={17} />
                  Добавить нашид
                </Button>
              )}
            </div>
          </div>
          <div className={styles.stats}>
            <div>
              <span>В каталоге</span>
              <strong>{data?.stats.published ?? "—"}</strong>
              <small>
                <i />
                Опубликованных нашидов
              </small>
            </div>
            <div>
              <span>Черновики</span>
              <strong>{data?.stats.drafts ?? "—"}</strong>
              <small>Готовятся к публикации</small>
            </div>
            <div>
              <span>На проверке</span>
              <strong>{data?.stats.pending ?? "—"}</strong>
              <small>Ожидают вашего решения</small>
            </div>
          </div>
          {(error || query.error) && (
            <div className={styles.error} role="alert">
              {error || message(query.error)}
              <Button
                variant="ghost"
                onClick={() => {
                  setError("");
                  void query.refetch();
                }}
              >
                Повторить
              </Button>
            </div>
          )}
          {notice && (
            <p className={styles.notice} role="status">
              <Check size={16} />
              {notice}
            </p>
          )}
          <section className={styles.collection} aria-label="Список записей">
            <div className={styles.filters}>
              <h2>
                {section === "catalog"
                  ? "Все нашиды"
                  : section === "submissions"
                    ? "Входящие материалы"
                    : section === "errors"
                      ? "Последние ошибки"
                      : "Последние изменения"}{" "}
                <span>{data?.total ?? "—"}</span>
              </h2>
              {(section === "catalog" || section === "submissions") && (
                <div className={styles.filterControls}>
                  <div className={styles.search}>
                    <Search size={16} />
                    <Input
                      value={search}
                      onChange={(e) => setSearch(e.target.value)}
                      placeholder="Название или исполнитель"
                      aria-label="Поиск"
                    />
                  </div>
                  <Choice
                    label="Статус"
                    value={status}
                    onChange={(s) => {
                      setStatus(s);
                      setPage(1);
                    }}
                    options={
                      section === "catalog"
                        ? [
                            ["all", "Все статусы"],
                            ["published", "Опубликованные"],
                            ["draft", "Черновики"],
                            ["archived", "Архив"],
                          ]
                        : [
                            ["all", "Все статусы"],
                            ["pending", "На проверке"],
                            ["published", "Одобренные"],
                            ["rejected", "Отклонённые"],
                            ["uploading", "Загружаются"],
                          ]
                    }
                  />
                </div>
              )}
            </div>
            {!data && query.isPending ? (
              <div className={styles.empty} aria-busy="true">
                Загружаем коллекцию…
              </div>
            ) : !data || data.total === 0 ? (
              <div className={styles.empty}>
                <Library size={26} />
                <h3>
                  {section === "history"
                    ? "Изменений пока нет"
                    : "Здесь пока нет записей"}
                </h3>
                <p>
                  {search
                    ? "Попробуйте другой запрос."
                    : section === "catalog"
                      ? "Добавьте первый нашид в коллекцию."
                      : section === "submissions"
                        ? "Нажмите «Обновить», чтобы проверить новые загрузки."
                        : "Ваши действия будут появляться здесь."}
                </p>
              </div>
            ) : section === "catalog" ? (
              <>
                <div className={styles.tableHeading}>
                  <span>НАШИД / ИСПОЛНИТЕЛЬ</span>
                  <span>ДЛИТЕЛЬНОСТЬ</span>
                  <span>СТАТУС</span>
                  <span>ДЕЙСТВИЯ</span>
                </div>
                {data.tracks.map((t) => (
                  <article className={styles.trackRow} key={t.id}>
                    <div className={styles.trackIdentity}>
                      {t.artworkUrl ? (
                        <img src={t.artworkUrl} alt="" loading="lazy" />
                      ) : (
                        <div className={styles.cover}>
                          <Library size={18} />
                        </div>
                      )}
                      <div>
                        <h3 dir="auto">{t.title}</h3>
                        <p>{t.artist}</p>
                        <small>
                          {t.language.toUpperCase()} ·{" "}
                          {t.captionsRevision > 0
                            ? `${t.captions.length} строк субтитров`
                            : "Без редакторских субтитров"}
                          {t.recognition
                            ? " · " + recognitionLabels[t.recognition.status]
                            : ""}
                        </small>
                      </div>
                    </div>
                    <span className={styles.duration}>
                      {minutes(t.duration)}
                    </span>
                    <span
                      className={`${styles.badge} ${t.status === "published" ? styles.published : ""}`}
                    >
                      {labels[t.status]}
                    </span>
                    <div className={styles.rowActions}>
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => setEditor(t)}
                      >
                        Изменить
                      </Button>
                      <Button
                        size="icon-sm"
                        variant="ghost"
                        aria-label={"Субтитры: " + t.title}
                        onClick={() => setCaptionTrack(t)}
                      >
                        <FileText size={17} />
                      </Button>
                      {t.status === "published" ? (
                        <Button
                          size="icon-sm"
                          variant="ghost"
                          disabled={busy}
                          aria-label={"Снять с публикации: " + t.title}
                          onClick={() => {
                            if (
                              window.confirm(
                                "Снять нашид с публикации? Сохранённые файлы и пользовательские данные останутся.",
                              )
                            )
                              void run(
                                {
                                  action: "set-status",
                                  trackId: t.id,
                                  revision: t.revision,
                                  status: "archived",
                                },
                                "Нашид снят с публикации.",
                              ).catch(() => {});
                          }}
                        >
                          <Archive size={17} />
                        </Button>
                      ) : (
                        <Button
                          size="icon-sm"
                          variant="ghost"
                          disabled={busy}
                          aria-label={"Опубликовать: " + t.title}
                          onClick={() => {
                            void run(
                              {
                                action: "set-status",
                                trackId: t.id,
                                revision: t.revision,
                                status: "published",
                              },
                              "Нашид опубликован.",
                            ).catch(() => {});
                          }}
                        >
                          <ArrowUpRight size={18} />
                        </Button>
                      )}
                    </div>
                  </article>
                ))}
              </>
            ) : section === "submissions" ? (
              data.submissions.map((s) => (
                <article className={styles.submissionRow} key={s.id}>
                  <div>
                    <h3 dir="auto">{s.title || "Незавершённая загрузка"}</h3>
                    <p>
                      {s.artist || "Метаданные ещё не отправлены"} ·{" "}
                      {date(s.updatedAt)}
                    </p>
                    {s.rejectionReason && <small>{s.rejectionReason}</small>}
                  </div>
                  <span className={styles.badge}>{labels[s.status]}</span>
                  {s.status === "pending" && (
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => setReview(s)}
                    >
                      Проверить <ArrowUpRight size={14} />
                    </Button>
                  )}
                </article>
              ))
            ) : section === "errors" ? (
              (data.errors ?? []).map((e) => (
                <article key={e.id} className={styles.event}>
                  <span className={styles.eventIcon}>
                    <Activity size={16} />
                  </span>
                  <div>
                    <h3>
                      {e.area} · {e.errorType} · {e.errorCode}
                    </h3>
                    <p>
                      {e.platform} {e.version} · build {e.build}
                    </p>
                  </div>
                  <time dateTime={e.occurredAt}>{date(e.occurredAt)}</time>
                </article>
              ))
            ) : (
              data.events.map((e) => (
                <article key={e.id} className={styles.event}>
                  <span className={styles.eventIcon}>
                    <History size={16} />
                  </span>
                  <div>
                    <h3>{eventLabels[e.action] ?? e.action}</h3>
                    <p>
                      {e.actor || "Администратор"} · <code>{e.entityId}</code>
                    </p>
                  </div>
                  <time dateTime={e.createdAt}>{date(e.createdAt)}</time>
                </article>
              ))
            )}
            <footer className={styles.pagination}>
              <span>Страница {page} · по 20 записей</span>
              <div>
                <Button
                  size="icon-sm"
                  variant="outline"
                  aria-label="Предыдущая страница"
                  disabled={page <= 1}
                  onClick={() => setPage((p) => p - 1)}
                >
                  <ChevronLeft size={17} />
                </Button>
                <Button
                  size="icon-sm"
                  variant="outline"
                  aria-label="Следующая страница"
                  disabled={!data || page * 20 >= data.total}
                  onClick={() => setPage((p) => p + 1)}
                >
                  <ChevronRight size={17} />
                </Button>
              </div>
            </footer>
          </section>
          <aside className={styles.captionInfo}>
            <FileText size={21} />
            <div>
              <h2>Субтитры — часть коллекции</h2>
              <p>
                {data?.recognition.message ??
                  "Готовые субтитры можно импортировать или отредактировать вручную."}
              </p>
            </div>
            <span className={styles.badge}>Без платных запросов</span>
          </aside>
          <footer className={styles.footer}>
            Muwa · Нашиды без музыки
            <span>Изменения сохраняются в общей базе Muwa</span>
          </footer>
        </div>
      </main>
      {editor !== undefined && (
        <TrackEditor
          track={editor}
          onClose={() => setEditor(undefined)}
          onSaved={async () => {
            setEditor(undefined);
            setNotice("Нашид сохранён.");
            await refresh();
          }}
          disabled={!!exampleState}
        />
      )}
      {captionTrack && (
        <CaptionEditor
          track={captionTrack}
          onClose={() => setCaptionTrack(null)}
          onSaved={async () => {
            setCaptionTrack(null);
            setNotice("Субтитры сохранены.");
            await refresh();
          }}
          disabled={!!exampleState}
        />
      )}
      {review && (
        <SubmissionReview
          submission={review}
          onClose={() => setReview(null)}
          onSaved={async () => {
            setReview(null);
            setNotice("Решение сохранено.");
            await refresh();
          }}
          disabled={!!exampleState}
        />
      )}
    </div>
  );
};
const TrackEditor = ({
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
const CaptionEditor = ({
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
                ? recognitionLabels[recognized.status]
                : "Автоматические субтитры"}
            </strong>
            <p>
              {recognized?.status === "processing"
                ? `Распознано ${minutes(recognized.progressSeconds)} из ${minutes(track.duration)}. Загрузка и прослушивание продолжают работать.`
                : recognized?.status === "failed"
                  ? "Распознавание не завершено. Исходный файл и сохранённые субтитры не изменены; можно повторить."
                  : recognized?.status === "ready"
                    ? "Проверьте слова и время по записи. Ручные исправления не заменяются автоматическим результатом."
                    : "Сервер распознаёт оригинал локально, по одному файлу. Новые загрузки попадают в очередь автоматически."}
            </p>
            {recognized?.quality?.needsReview && (
              <p>
                Есть неуверенно распознанные фразы или язык. Проверьте текст
                перед сохранением.
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
            {busy ? "Сохраняем…" : "Сохранить субтитры"}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
};
const SubmissionReview = ({
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
