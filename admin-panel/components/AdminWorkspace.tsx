import { ArrowUpRight } from "lucide-react";
import { Button } from "./Button";
import { PasswordLoginForm } from "./PasswordLoginForm";
import { useAuth } from "../helpers/useAuth";
import { logo } from "../helpers/adminPresentation";
import { AdminConsole } from "../features/workspace/AdminConsole";
import styles from "./AdminWorkspace.module.css";

// Stable public entry point for production and development examples.
export { AdminConsole } from "../features/workspace/AdminConsole";

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
