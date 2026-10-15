import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { getAdminState } from "../../../backend/endpoints/admin/state_GET.schema";
import { postAdminAction } from "../../../backend/endpoints/admin/action_POST.schema";
import type {
  AdminState,
  AdminQuery,
  AdminAction,
} from "../../../backend/helpers/adminValidation";
import { message } from "../../helpers/adminPresentation";

// Single owner of filters, server queries and mutation feedback.
export function useAdminWorkspace(exampleState?: AdminState) {
  const client = useQueryClient();
  const [section, setSection] = useState<AdminQuery["section"]>("catalog"),
    [search, setSearch] = useState(""),
    [querySearch, setQuerySearch] = useState(""),
    [status, setStatus] = useState("all"),
    [page, setPage] = useState(1);
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
  return {
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
  };
}
