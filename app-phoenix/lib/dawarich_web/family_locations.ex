defmodule DawarichWeb.FamilyLocations do
  @moduledoc false

  import Plug.Conn

  alias Dawarich.{Accounts, FamilyPage, Families.Locations}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.LayoutAssigns

  def init(action), do: action

  def native?(conn, _params) do
    query = Plug.Conn.Query.decode(conn.query_string)

    conn.method in ["GET", "HEAD"] and DawarichWeb.FamilyGate.session_supported?(conn) and
      not Enum.any?(~w(format locale), &Map.has_key?(query, &1))
  end

  def call(conn, _action) do
    user = conn.assigns.current_user && Accounts.get(conn.assigns.current_user.id)

    case result(user, conn.assigns[:now] || DateTime.utc_now()) do
      {status, locations} ->
        conn
        |> put_resp_header("cache-control", "private, no-store")
        |> put_resp_content_type("application/json")
        |> send_resp(status, Ruby.json(locations))
    end
  rescue
    _error -> conn |> put_resp_content_type("application/json") |> send_resp(500, "[]") |> halt()
  end

  defp result(nil, _now), do: {401, []}

  defp result(user, now) do
    case FamilyPage.read(user, :show, now: now, self_hosted: LayoutAssigns.self_hosted?()) do
      {:ok, %{state: :show}} -> project(user, now)
      {:redirect, _path, :not_in_family} -> {404, []}
      {:redirect, _path, :feature_unavailable} -> {403, []}
      _other -> {500, []}
    end
  rescue
    _error -> {500, []}
  end

  defp project(user, now) do
    case Locations.read(Map.put(user, :timezone, user.settings["timezone"]), now) do
      {:ok, 200, {:object, pairs}} ->
        locations =
          pairs
          |> List.keyfind("locations", 0)
          |> elem(1)
          |> Enum.sort_by(fn {:object, fields} -> List.keyfind(fields, "email", 0) |> elem(1) end)
          |> Enum.map(fn {:object, fields} ->
            {:object,
             Enum.filter(fields, fn {key, _} ->
               key in ~w(user_id email name latitude longitude timestamp updated_at)
             end)}
          end)

        {200, locations}

      _other ->
        {500, []}
    end
  end
end
