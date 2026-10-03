defmodule DawarichWeb.AchievementInitial do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _) do
    if DawarichWeb.AchievementPageGate.open?(conn, conn.path_params) do
      render_page(conn)
    else
      conn
      |> assign(:api_tag, "achievement collection")
      |> DawarichWeb.Api.Body.replay("query parameter shape")
    end
  end

  defp render_page(conn) do
    params = Map.merge(conn.query_params, conn.path_params)

    context =
      DawarichWeb.AchievementContext.for_user(conn.assigns.current_user, conn.assigns.locale)

    {:ok, view} =
      Dawarich.Achievements.Collection.load(
        Dawarich.Repo,
        conn.assigns.current_user.id,
        params,
        context
      )

    keys =
      if(view[:set], do: [view.set], else: view.sets ++ view.orphans)
      |> Enum.filter(& &1["celebrate"])
      |> Enum.map(& &1["key"])

    conn |> assign(:achievement_page, view) |> assign(:achievement_celebrations, keys)
  end
end
