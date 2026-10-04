import { useState, type FormEvent } from "react";
import { Input } from "./Input";
import { Button } from "./Button";
import { useAuth } from "../helpers/useAuth";
import styles from "./AdminWorkspace.module.css";

export function OwnerSetup({ token, onComplete }: { token: string; onComplete: () => void }) {
  const { onLogin } = useAuth();
  const [password, setPassword] = useState("");
  const [repeat, setRepeat] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  async function submit(event: FormEvent) {
    event.preventDefault(); setError("");
    if (password.length < 12 || new TextEncoder().encode(password).length > 72) { setError("Используйте от 12 символов, максимум 72 байта."); return; }
    if (password !== repeat) { setError("Пароли не совпадают."); return; }
    setBusy(true);
    try {
      const response = await fetch("/_api/auth/owner_setup", { method: "POST", credentials: "same-origin", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ token, password }) });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Не удалось завершить настройку.");
      setPassword(""); setRepeat(""); onLogin(result.user); onComplete();
    } catch (e) { setError(e instanceof Error ? e.message : "Проверьте соединение."); }
    finally { setBusy(false); }
  }
  if (window.self !== window.top) return <main className={styles.gate}>Откройте ссылку в отдельном окне.</main>;
  return <main className={styles.gate}><div className={styles.login}>
    <img src="/assets/app-mark.png" alt="Muwa" />
    <span className={styles.eyebrow}>MUWA / ПЕРВЫЙ ВХОД</span>
    <h1>Ваш новый каталог</h1><p>Задайте пароль владельца. Затем можно загружать и публиковать нашиды.</p>
    <form onSubmit={submit} style={{display:"grid",gap:"1rem"}}>
      <label>Новый пароль<Input type="password" required minLength={12} autoComplete="new-password" value={password} onChange={e => setPassword(e.target.value)} disabled={busy} /></label>
      <label>Повторите пароль<Input type="password" required autoComplete="new-password" value={repeat} onChange={e => setRepeat(e.target.value)} disabled={busy} /></label>
      {error && <p role="alert">{error}</p>}
      <Button type="submit" disabled={busy}>{busy ? "Создаём аккаунт…" : "Открыть панель"}</Button>
    </form>
  </div></main>;
}
