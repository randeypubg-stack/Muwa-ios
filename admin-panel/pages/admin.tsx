import { Helmet } from "react-helmet";
import { AdminWorkspace } from "../components/AdminWorkspace";
export default function AdminPage() {
  return (
    <>
      <Helmet>
        <title>Muwa — панель управления</title>
        <meta name="robots" content="noindex,nofollow" />
      </Helmet>
      <AdminWorkspace />
    </>
  );
}
