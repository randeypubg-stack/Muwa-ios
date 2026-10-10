import { useEffect, useState } from "react";
import { AdminWorkspace } from "../components/AdminWorkspace";
import { OwnerSetup } from "../components/OwnerSetup";
function takeSetupToken() {
  const token = /^#setup=([a-f0-9]{64})$/.exec(window.location.hash)?.[1];
  if (token) window.history.replaceState(null, "", "/admin");
  return token;
}
// Capture once before StrictMode mounts; never retain the capability in the URL.
const initialSetupToken = takeSetupToken();
export default function AdminPage() {
  const [token, setToken] = useState(initialSetupToken);
  useEffect(() => {
    const changed = () => { const next = takeSetupToken(); if (next) setToken(next); };
    window.addEventListener("hashchange", changed);
    return () => window.removeEventListener("hashchange", changed);
  }, []);
  return (
    <>
      <title>Muwa — панель управления</title>
      <meta name="robots" content="noindex,nofollow" />
      {token ? <OwnerSetup token={token} onComplete={() => setToken(undefined)} /> : <AdminWorkspace />}
    </>
  );
}
