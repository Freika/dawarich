defmodule Dawarich.Stats.ApiClosure do
  @moduledoc false
  alias Dawarich.{
    Accounts,
    CountriesAndCities,
    Distance,
    Jsonb,
    Flights,
    I18n,
    RailsTime,
    Repo,
    Residency,
    RubyInteger
  }

  alias Dawarich.AccountApi.Closure, as: Account
  alias Dawarich.Geocoding.Config
  alias Dawarich.Stats.{Heatmap, Insights, Summary, Toponyms}
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
    render = if action == :insights, do: &Insights.overview/3, else: &Insights.details/3

    with {:ok, unit} <- Params.unit(params["distance_unit"], Accounts.settings(user.id)),
         {:ok, frame} <-
           RailsTime.with_zone(user.timezone, fn -> Insights.frame(user.id, requested, now) end),
         frame = scoped_frame(frame, user, requested, full, now),
         {:ok, {:object, fields}} <- render.(user.id, frame, unit),
         {:ok, fields} <- scoped_fields(action, fields, frame, user, unit, full, now) do
      fields =
        replace(fields, %{
          "planRestricted" => not full,
          "upgradeUrl" => Account.upgrade_url(user, now)
        })

      {:ok, {:object, fields}, cache_control: "max-age=300, private"}
    end
  end

  defp scoped_frame(frame, _user, _requested, true, _now), do: frame

  defp scoped_frame(frame, user, requested, false, now) do
    cutoff = cutoff(user, now)

    years =
      Repo.query!(
        "SELECT DISTINCT year FROM stats WHERE user_id=$1 AND (year>$2 OR (year=$2 AND month >=$3)) ORDER BY year DESC",
        [user.id, elem(cutoff, 0), elem(cutoff, 1)]
      ).rows
      |> List.flatten()

    selected = requested || List.first(years) || frame.today.year

    {:ok, scoped} =
      RailsTime.with_zone(user.timezone, fn -> Insights.frame(user.id, selected, now) end)

    Map.merge(scoped, %{years: years, cutoff: cutoff})
  end

  defp cutoff(user, now) do
    epoch = Dawarich.MapApi.Closure.window(user, now)

    [[year, month]] =
      Repo.query!(
        "SELECT extract(year FROM to_timestamp($1) AT TIME ZONE $2)::integer, extract(month FROM to_timestamp($1) AT TIME ZONE $2)::integer",
        [epoch, user.timezone]
      ).rows

    {year, month, epoch}
  end

  defp scoped_fields(_action, fields, _frame, _user, _unit, true, _now), do: {:ok, fields}

  defp scoped_fields(action, fields, frame, user, unit, false, _now) do
    with {:ok, stats} <- scoped_stats(user.id, frame.year, frame.cutoff) do
      totals = totals(stats, unit)

      if action == :insights do
        {:ok,
         replace(fields, %{
           "availableYears" => frame.years,
           "totals" =>
             {:object,
              Enum.map(
                ~w(totalDistance distanceUnit countriesCount citiesCount countriesList daysTraveling biggestMonth),
                &{&1, totals[&1]}
              )},
           "activityHeatmap" => Heatmap.term(stats, frame.year, frame.today)
         })}
      else
        with {:ok, previous} <- scoped_stats(user.id, frame.year - 1, frame.cutoff) do
          {:object, patterns} = List.keyfind(fields, "travelPatterns", 0) |> elem(1)

          patterns =
            replace(patterns, %{
              "topVisitedLocations" => scoped_visits(user.id, frame.visits, elem(frame.cutoff, 2))
            })

          {:ok,
           replace(fields, %{
             "comparison" => comparison(frame.year, totals, previous, unit),
             "travelPatterns" => {:object, patterns}
           })}
        end
      end
    end
  end

  defp scoped_stats(owner, year, {cut_year, cut_month, _}) do
    Repo.query!(
      "SELECT month,distance,toponyms,daily_distance::text FROM stats WHERE user_id=$1 AND year=$2 AND (year>$3 OR (year=$3 AND month >=$4)) ORDER BY month",
      [owner, year, cut_year, cut_month]
    ).rows
    |> Enum.reduce_while({:ok, []}, fn [month, distance, places, daily], {:ok, rows} ->
      case Heatmap.pairs(Jsonb.decode(daily)) do
        {:ok, pairs} ->
          {:cont,
           {:ok,
            rows ++
              [
                %{
                  year: year,
                  month: month,
                  distance: distance,
                  toponyms: Toponyms.sanitize(places),
                  daily: pairs
                }
              ]}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp totals(stats, unit) do
    places = Enum.flat_map(stats, & &1.toponyms)

    biggest =
      Enum.reduce(stats, nil, fn stat, best ->
        if best == nil or stat.distance > best.distance, do: stat, else: best
      end)

    biggest =
      if biggest && biggest.distance > 0,
        do:
          {:object,
           [
             {"month", Calendar.strftime(Date.new!(biggest.year, biggest.month, 1), "%B")},
             {"distance", round(Distance.convert(biggest.distance, unit))}
           ]},
        else: nil

    %{
      "totalDistance" => round(Distance.convert(Enum.sum(Enum.map(stats, & &1.distance)), unit)),
      "distanceUnit" => unit,
      "countriesCount" => length(Toponyms.countries(places)),
      "citiesCount" => length(Toponyms.cities(places)),
      "countriesList" => Toponyms.countries(places),
      "daysTraveling" =>
        Enum.sum(Enum.map(stats, fn s -> Enum.count(s.daily, fn {_, _, n} -> n > 0 end) end)),
      "biggestMonth" => biggest
    }
  end

  defp comparison(_year, _current, [], _unit), do: nil

  defp comparison(year, current, rows, unit) do
    previous = totals(rows, unit)

    {:object,
     [
       {"previousYear", year - 1},
       {"distanceChangePercent", change(current["totalDistance"], previous["totalDistance"])},
       {"countriesChange", current["countriesCount"] - previous["countriesCount"]},
       {"citiesChange", change(current["citiesCount"], previous["citiesCount"])},
       {"daysChange", change(current["daysTraveling"], previous["daysTraveling"])}
     ]}
  end

  defp change(_current, 0), do: 0
  defp change(current, previous), do: round((current - previous) / previous * 100)

  defp scoped_visits(owner, {from, to}, cutoff) do
    Repo.query!(
      "SELECT name,count(*),sum(duration) FROM visits WHERE user_id=$1 AND deleted_at IS NULL AND status=1 AND started_at BETWEEN $2 AND $3 AND started_at>=to_timestamp($4) AT TIME ZONE 'UTC' GROUP BY name ORDER BY count(*) DESC,sum(duration) DESC LIMIT 5",
      [owner, from, to, cutoff]
    ).rows
    |> Enum.map(fn [name, count, duration] ->
      {:object, [{"name", name}, {"visitCount", count}, {"totalDuration", duration}]}
    end)
  end

  defp replace(fields, changes),
    do: Enum.map(fields, fn {key, value} -> {key, Map.get(changes, key, value)} end)

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
