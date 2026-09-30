defmodule DawarichWeb.Api.StatsController do
  @moduledoc false
  @behaviour Plug

  alias Dawarich.{Accounts, RailsTime, Repo, Residency}
  alias Dawarich.Geocoding.Config
  alias Dawarich.Stats.{Insights, Summary}
  alias DawarichWeb.Api.{Body, Params, Respond}

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, action) do
    case read(action, conn.assigns.api_user, conn.assigns.api_params) do
      {:ok, term, opts} -> Respond.json(conn, 200, term, opts)
      {:replay, reason} -> Body.replay(conn, reason)
    end
  end

  defp read(action, user, params) do
    run(action, user, params)
  rescue
    error -> {:replay, inspect(error.__struct__)}
  end

  defp run(:index, user, _params),
    do: {:ok, Summary.term(user.id, Config.resolve(Repo).store_geodata, DateTime.utc_now()), []}

  defp run(:residency, user, params) do
    with {:ok, year} <- Params.year(params["year"]),
         {:ok, window} <-
           RailsTime.with_zone(user.timezone, fn ->
             Residency.window(user.id, year, DateTime.utc_now())
           end),
         {:ok, term} <- Residency.term(user.id, window),
         do: {:ok, term, []}
  end

  defp run(action, user, params) do
    render = if action == :insights, do: &Insights.overview/3, else: &Insights.details/3

    with {:ok, year} <- Params.year(params["year"]),
         {:ok, unit} <- Params.unit(params["distance_unit"], Accounts.settings(user.id)),
         {:ok, frame} <-
           RailsTime.with_zone(user.timezone, fn ->
             Insights.frame(user.id, year, DateTime.utc_now())
           end),
         {:ok, term} <- render.(user.id, frame, unit),
         do: {:ok, term, cache_control: "max-age=300, private"}
  end
end
