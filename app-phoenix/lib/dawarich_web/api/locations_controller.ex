defmodule DawarichWeb.Api.LocationsController do
  @moduledoc false
  @behaviour Plug

  alias Dawarich.{I18n, Locations, RailsTime}
  alias DawarichWeb.Api.{Body, Params, Respond}

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, :index_closure),
    do:
      closure(
        conn,
        Dawarich.Locations.Closure.read(conn.assigns.api_user, conn.assigns.api_params)
      )

  def call(conn, :suggestions),
    do:
      closure(
        conn,
        Dawarich.Locations.Suggestions.run(conn.assigns.api_user, conn.assigns.api_params)
      )

  def call(conn, :index) do
    params = conn.assigns.api_params

    case Params.coordinates(params["lat"], params["lon"]) do
      :missing ->
        bad_request(conn, "coordinates_lat_lon_are_required")

      {:ok, lat, lon} when abs(lat) > 90 or abs(lon) > 180 ->
        bad_request(conn, "invalid_coordinates_lat_must_be_90_90_lon_must_be")

      {:ok, lat, lon} ->
        answer(conn, lat, lon)

      {:replay, reason} ->
        Body.replay(conn, reason)
    end
  end

  defp answer(conn, lat, lon) do
    case read(conn.assigns.api_user, conn.assigns.api_params, lat, lon) do
      {:ok, term} -> Respond.json(conn, 200, term)
      {:replay, reason} -> Body.replay(conn, reason)
    end
  end

  defp read(user, params, lat, lon) do
    with {:ok, search} <- search(params, lat, lon),
         {:ok, rows} <-
           RailsTime.with_zone(user.timezone, fn -> {:ok, Locations.rows(user.id, search)} end),
         do: Locations.term(search, rows)
  rescue
    error -> {:replay, inspect(error.__struct__)}
  end

  defp search(params, lat, lon) do
    with {:ok, limit} <- Params.count(params["limit"], 50),
         {:ok, radius} <- Params.count(params["radius_override"], 500),
         {:ok, from} <- Params.date(params["date_from"]),
         {:ok, to} <- Params.date(params["date_to"]),
         {:ok, name} <- Params.text(params["name"]),
         {:ok, address} <- Params.text(params["address"]) do
      {:ok,
       %{
         lat: lat,
         lon: lon,
         limit: limit,
         radius: radius,
         date_from: from,
         date_to: to,
         name: name,
         address: address
       }}
    end
  end

  defp bad_request(conn, key),
    do:
      Respond.json(
        conn,
        400,
        {:object, [{"error", I18n.en!("controllers.api.v1.locations." <> key)}]}
      )

  defp closure(conn, {:ok, status, term}), do: Respond.json(conn, status, term)
end
