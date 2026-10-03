defmodule DawarichWeb.AchievementSession do
  @moduledoc false
  def live_session(conn) do
    DawarichWeb.RailsAuth.live_session(conn)
    |> Map.put("achievement_celebrations", conn.assigns[:achievement_celebrations] || [])
  end

  def celebrations(_session, %{"_mounts" => mounts}) when is_integer(mounts) and mounts > 0,
    do: []

  def celebrations(session, _connect_params), do: session["achievement_celebrations"] || []
end
