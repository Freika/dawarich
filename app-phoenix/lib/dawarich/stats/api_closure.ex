defmodule Dawarich.Stats.ApiClosure do
  @moduledoc false
  alias Dawarich.{
    Accounts,
    CountriesAndCities,
    Flights,
    I18n,
    RailsTime,
    Repo,
    Residency,
    RubyInteger
  }

  alias Dawarich.AccountApi.Closure, as: Account
  alias Dawarich.Geocoding.Config
  alias Dawarich.Stats.{Insights, Summary}
  alias DawarichWeb.Api.Params

  def read(action, user, params, now) do
    with :ok <- Account.pending(user, now) do
      user = %{user | timezone: Account.zone(user.timezone)}

      case action do
        :residency -> residency(user, params, now)
        :index -> {:ok, Summary.term(user.id, Config.resolve(Repo).store_geodata, now), []}
        action when action in [:insights, :details] -> insights(action, user, params, now)
        action -> geo(action, user, params, now)
      end
      |> terminal()
    else
      {:ok, status, term} -> {:error, status, term}
    end
  rescue
    _ -> {:error, 500, error("internal_server_error")}
  end

  defp residency(user, params, now) do
    if Account.full?(user, now) do
      with {:ok, window} <-
             RailsTime.with_zone(user.timezone, fn ->
               Residency.window(user.id, year(params["year"]), now)
             end),
           {:ok, term} <- Residency.term(user.id, window),
           do: {:ok, term, []}
    else
      {:error, 403,
       {:object,
        [
          {"error", "pro_plan_required"},
          {"message", I18n.en!("controllers.api.this_feature_requires_a_pro_plan")},
          {"upgrade_url", Account.upgrade_url(user, now)}
        ]}}
    end
  end

  defp insights(action, user, params, now) do
    full = Account.full?(user, now)
    requested = year(params["year"])

    if not full and (action == :details or (requested != nil and requested < now.year)) do
      {:error, 422, error("Unprocessable Entity")}
    else
      render = if action == :insights, do: &Insights.overview/3, else: &Insights.details/3

      with {:ok, unit} <- Params.unit(params["distance_unit"], Accounts.settings(user.id)),
           {:ok, frame} <-
             RailsTime.with_zone(user.timezone, fn -> Insights.frame(user.id, requested, now) end),
           true <- full or frame.year >= now.year,
           {:ok, {:object, fields}} <- render.(user.id, frame, unit) do
        fields =
          Enum.map(fields, fn
            {"planRestricted", _} ->
              {"planRestricted", not full}

            {"upgradeUrl", _} ->
              {"upgradeUrl", Account.upgrade_url(user, now)}

            {"availableYears", years} when not full ->
              {"availableYears", Enum.filter(years, &(&1 >= now.year))}

            pair ->
              pair
          end)

        {:ok, {:object, fields}, cache_control: "max-age=300, private"}
      else
        false -> {:error, 422, error("Unprocessable Entity")}
        other -> other
      end
    end
  end

  defp geo(:visited_cities, user, params, now) do
    with {:ok, from} <- Params.timestamp(params["start_at"]),
         {:ok, to} <- Params.timestamp(params["end_at"]),
         {:ok, minutes} <- Params.min_minutes(Accounts.settings(user.id)),
         {:ok, range} <-
           RailsTime.with_zone(user.timezone, fn ->
             {:ok, CountriesAndCities.range(from, to, now)}
           end),
         do: {:ok, CountriesAndCities.term(user.id, range, minutes), []}
  end

  defp geo(:flights, user, params, now) do
    with {:ok, filter} <- Params.flight_filter(params["start_at"], params["end_at"]),
         do:
           RailsTime.with_zone(user.timezone, fn ->
             {:ok, Flights.term(user.id, filter, now), []}
           end)
  end

  defp year(nil), do: nil
  defp year(value) when is_binary(value) or is_integer(value), do: RubyInteger.to_i(value)
  defp year(_), do: raise(ArgumentError)
  defp terminal({:replay, _}), do: {:error, 500, error("internal_server_error")}
  defp terminal(result), do: result
  defp error(message), do: {:object, [{"error", message}]}
end
