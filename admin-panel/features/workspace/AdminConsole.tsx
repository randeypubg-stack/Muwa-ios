import { useState } from "react";
import {
  Library,
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
} from "lucide-react";
import { Button } from "../../components/Button";
import { Input } from "../../components/Input";
import { Choice } from "../../components/Choice";
import type {
  AdminState,
  TrackRecord,
  SubmissionRecord,
} from "../../../backend/helpers/adminValidation";
import {
  labels,
  recognitionLabel,
  eventLabels,
  minutes,
  date,
  message,
  logo,
} from "../../helpers/adminPresentation";
import { TrackEditor } from "../catalog/TrackEditor";
import { CaptionEditor } from "../captions/CaptionEditor";
import { SubmissionReview } from "../submissions/SubmissionReview";
import { useAdminWorkspace } from "./useAdminWorkspace";
import styles from "../../components/AdminWorkspace.module.css";

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
  const {
    section,
    search,
    setSearch,
    status,
    setStatus,
    page,
    setPage,
    error,
    setError,
    notice,
    setNotice,
    busy,
    query,
    data,
    refresh,
    run,
    navigate,
  } = useAdminWorkspace(exampleState);
  const [editor, setEditor] = useState<TrackRecord | null | undefined>(
      undefined,
    ),
    [captionTrack, setCaptionTrack] = useState<TrackRecord | null>(null),
    [review, setReview] = useState<SubmissionRecord | null>(null);
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
          {section === "catalog" &&
            data?.recognition.enabled &&
            data.recognition.counts && (
              <section
                className={styles.recognitionSummary}
                aria-label="Распознавание каталога"
                aria-live="polite"
              >
                <div>
                  <strong>Автоматические субтитры</strong>
                  <p>
                    Новые аудио распознаются на сервере. Оригинал сохраняется на
                    языке записи; публикация не ждёт распознавания.
                  </p>
                </div>
                <dl>
                  {(
                    [
                      ["В очереди", "queued"],
                      ["Обрабатывается", "processing"],
                      ["Готово", "ready"],
                      ["Проверить текст", "review"],
                      ["Ошибка", "failed"],
                      ["Без результата", "missing"],
                    ] as const
                  ).map(([label, key]) => (
                    <div key={key}>
                      <dt>{label}</dt>
                      <dd>{data.recognition.counts![key]}</dd>
                    </div>
                  ))}
                </dl>
              </section>
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
                            : "Субтитры ещё не опубликованы"}
                          {t.recognition
                            ? " · " + recognitionLabel(t.recognition)
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
