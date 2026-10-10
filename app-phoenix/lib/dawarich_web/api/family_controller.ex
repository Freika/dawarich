defmodule DawarichWeb.Api.FamilyController do
  @moduledoc false
  @behaviour Plug

  alias Dawarich.Families.{History, Locations, Mine, Requests, SharingUpdate}
  alias DawarichWeb.Api.{Body, Respond}

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, action) do
    params = Map.merge(conn.assigns.api_params, conn.path_params)

    case run(action, conn.assigns.api_user, params, conn.assigns[:api_now] || DateTime.utc_now()) do
      {:ok, status, term} -> Respond.json(conn, status, term)
      {:replay, reason} -> Body.replay(conn, reason)
    end
  end

  def run(action, user, params, now) do
    if Dawarich.Standalone.enabled?(),
      do: Dawarich.FamilyApi.Closure.run(action, user, params, now),
      else: dispatch(action, user, params, now)
  rescue
    error -> {:replay, inspect(error.__struct__)}
  end

  defp dispatch(:locations, user, _params, now), do: Locations.read(user, now)
  defp dispatch(:mine, user, _params, now), do: Mine.read(user, now)
  defp dispatch(:history, user, params, now), do: History.read(user, params, now)
  defp dispatch(:sharing, user, params, now), do: SharingUpdate.call(user, params, now)
  defp dispatch(:create, user, params, now), do: Requests.create(user, params, now)

  defp dispatch(decision, user, params, now) when decision in [:accept, :decline],
    do: Requests.respond(user, decision, params, now)
end
