defmodule DawarichWeb.IntegrationActions do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.{Locale, RailsSession, RequestURL, SettingsActions}

  def enabled?(_conn, _params), do: Dawarich.Standalone.enabled?()

  def admit(conn, methods, query_keys) do
    query = conn.assigns.api_query

    if Enum.any?(query, fn {key, value} -> key not in query_keys or not is_binary(value) end),
      do: {:error, 422},
      else: SettingsActions.admit(assign(conn, :api_query, %{}), methods)
  end

  def hosted?(conn),
    do: Map.get_lazy(conn.assigns, :self_hosted, &Dawarich.ReleaseMigration.self_hosted?/0)

  def locale(conn), do: Locale.resolve(nil, conn.assigns.current_user, conn.assigns.rails_session)

  def redirect(conn, path, flashes, status \\ 302) do
    conn
    |> RailsSession.stage(%{"flash" => %{"discard" => [], "flashes" => flashes}})
    |> put_resp_header("location", RequestURL.base(conn) <> path)
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(status, "")
    |> halt()
  end
end
