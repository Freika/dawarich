defmodule DawarichWeb.Api.GeoController do
  @moduledoc false
  @behaviour Plug

  alias Dawarich.{Accounts, CountriesAndCities, Flights, I18n, RailsTime}
  alias DawarichWeb.Api.{Body, Params, Respond}

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, :visited_cities) do
    case Params.missing(conn.assigns.api_params, ~w(start_at end_at)) do
      [] ->
        answer(conn, :visited_cities)

      missing ->
        {:ok, message} =
          I18n.t("en", "controllers.api.missing_required_parameters_join", %{
            "parameters" => Enum.join(missing, ", ")
          })

        Respond.json(conn, 400, {:object, [{"error", message}]})
    end
  end

  def call(conn, :flights), do: answer(conn, :flights)

  defp answer(conn, action) do
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

  defp run(:visited_cities, user, params) do
    with {:ok, from} <- Params.timestamp(params["start_at"]),
         {:ok, to} <- Params.timestamp(params["end_at"]),
         {:ok, minutes} <- Params.min_minutes(Accounts.settings(user.id)),
         {:ok, range} <-
           RailsTime.with_zone(user.timezone, fn ->
             {:ok, CountriesAndCities.range(from, to, DateTime.utc_now())}
           end),
         do: {:ok, CountriesAndCities.term(user.id, range, minutes), []}
  end

  defp run(:flights, user, params) do
    with {:ok, filter} <- Params.flight_filter(params["start_at"], params["end_at"]),
         do:
           RailsTime.with_zone(user.timezone, fn ->
             {:ok, Flights.term(user.id, filter, DateTime.utc_now()), []}
           end)
  end
end
