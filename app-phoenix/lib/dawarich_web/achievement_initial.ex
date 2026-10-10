defmodule DawarichWeb.AchievementInitial do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _) do
    with {:ok, _} <- Dawarich.Accounts.settings_for(conn.assigns.current_user),
         true <- DawarichWeb.AchievementPageGate.open?(conn, conn.path_params) do
      render_page(conn)
    else
      {:error, :unsupported} ->
        if Dawarich.Standalone.enabled?(),
          do: DawarichWeb.StandaloneError.respond(conn, "achievement_settings"),
          else: replay(conn)

      false ->
        replay(conn)
    end
  end

  defp replay(conn) do
    conn
    |> assign(:api_tag, "achievement collection")
    |> DawarichWeb.Api.Body.replay("query parameter shape")
  end

  defp render_page(conn) do
    params = Map.merge(conn.query_params, conn.path_params)

    context =
      DawarichWeb.AchievementContext.for_user(conn.assigns.current_user, conn.assigns.locale)

    result =
      Dawarich.Achievements.Collection.load(
        Dawarich.Repo,
        conn.assigns.current_user.id,
        params,
        context
      )

    case result do
      {:ok, view} ->
        loaded(conn, view)

      {:redirect, path} ->
        conn |> put_resp_header("location", path) |> send_resp(302, "") |> halt()

      {:error, :not_found} ->
        conn |> send_resp(404, "") |> halt()
    end
  end

  defp loaded(conn, view) do
    keys =
      if(view[:set], do: [view.set], else: view.sets ++ view.orphans)
      |> Enum.filter(& &1["celebrate"])
      |> Enum.map(& &1["key"])

    conn |> assign(:achievement_page, view) |> assign(:achievement_celebrations, keys)
  end
end
