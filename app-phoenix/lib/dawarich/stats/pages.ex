defmodule Dawarich.Stats.Pages do
  @moduledoc false
  alias Dawarich.Analytics.Period
  alias Dawarich.{Stats, Repo, LocalTime, RubyInteger, RubyFloat}
  alias Dawarich.Stats.Toponyms

  def index(scope, params \\ %{}, opts \\ []) do
    with {:ok, scope, period} <- Period.admit(scope, params, :index, opts) do
      rows =
        Repo.query!(
          "SELECT year,month,distance,toponyms,(updated_at AT TIME ZONE 'UTC' AT TIME ZONE $2)::date FROM stats WHERE user_id=$1 ORDER BY year DESC,updated_at DESC",
          [scope.user.id, period.zone], log: false).rows
        |> Enum.map(fn [year, month, distance, toponyms, updated] ->
          %{
            year: year,
            month: month,
            distance: distance,
            toponyms: Period.narrow(toponyms),
            updated_on: updated
          }
        end)

      admitted = Enum.filter(rows, &Stats.in_window?(&1, period.cutoff))

      years =
        admitted
        |> Enum.chunk_by(& &1.year)
        |> Enum.map(fn [first | _] = stats ->
          %{
            year: first.year,
            updated_on: first.updated_on,
            stats: stats,
            distances: distances(stats)
          }
        end)

      all_years = rows |> Enum.map(& &1.year) |> Enum.uniq()
      visible = Enum.slice(all_years, (period.page - 1) * 50, 50)
      total_pages = ceil(length(all_years) / 50)
      all = Enum.flat_map(rows, & &1.toponyms)
      counts = ready_counts(scope.user, period, opts)

      {:ok,
       %{
         years: Enum.filter(years, &(&1.year in visible)),
         total_pages: total_pages,
         page: period.page,
         more: period.page < total_pages,
         locked_years:
           if(period.restricted,
             do: Enum.filter(all_years -- Enum.map(years, & &1.year), &(&1 in visible)),
             else: []
           ),
         total_distance: Enum.sum(Enum.map(rows, & &1.distance)),
         countries_visited: Toponyms.countries(all),
         cities_visited: Toponyms.cities(all),
         points: counts,
         unit: period.unit,
         restricted: period.restricted,
         period: period,
         active: scope.user.status == 1
       }}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def year(scope, params, opts \\ []) do
    with {:ok, scope, period} <- Period.admit(scope, params, :year, opts) do
      data = Stats.year(scope.user, period.year, period)
      stats = Enum.map(data.stats, &%{&1 | toponyms: Period.narrow(&1.toponyms)})

      {:ok,
       Map.merge(%{data | stats: stats}, %{
         year: period.year,
         unit: period.unit,
         period: period,
         restricted: period.restricted
       })}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def month(scope, params, opts \\ []) do
    with {:ok, scope, period} <- Period.admit(scope, params, :month, opts),
         data = Stats.month(scope.user, period.year, period.month, period),
         {:ok, stat} <- stat(data.stat),
         {:ok, previous} <- stat(data.previous) do
      daily = if stat, do: stat.daily, else: []

      peak =
        case Enum.max_by(daily, fn [_, meters] -> meters end, &>=/2, fn -> nil end) do
          [day, meters] when meters > 0 -> {day, meters}
          _ -> nil
        end

      bounds =
        if peak,
          do:
            LocalTime.day_bounds(period.zone, Date.new!(period.year, period.month, elem(peak, 0)))

      {:ok,
       %{
         year: period.year,
         month: period.month,
         data: %{data | stat: stat, previous: previous},
         peak: peak,
         bounds: bounds,
         unit: period.unit,
         period: period,
         restricted: period.restricted
       }}
    end
  rescue
    _ -> {:error, :invalid_input}
  end

  defp stat(nil), do: {:ok, nil}

  defp stat(stat) do
    with {:ok, daily} <- daily(stat.daily, stat.year, stat.month) do
      {:ok,
       stat
       |> Map.drop([:sharing_uuid])
       |> Map.put(:toponyms, Period.narrow(stat.toponyms))
       |> Map.put(:daily, daily)}
    end
  end

  def daily(value, year, month) when is_map(value),
    do: daily(Enum.map(value, fn {day, meters} -> [day, meters] end), year, month)

  def daily(value, year, month) when is_list(value) and length(value) <= 31 do
    Enum.reduce_while(value, {:ok, []}, fn
      [day, meters], {:ok, acc} ->
        day = RubyInteger.to_i(day)

        with true <- is_number(meters), {:ok, date} <- Date.new(year, month, day) do
          {:cont, {:ok, acc ++ [[date.day, meters]]}}
        else
          _ -> {:halt, {:error, :invalid_input}}
        end

      _, _ ->
        {:halt, {:error, :invalid_input}}
    end)
  end

  def daily(_, _, _), do: {:error, :invalid_input}

  defp ready_counts(user, period, opts) do
    generation = Dawarich.AfterCommit.Visibility.generation(Repo, user.id)

    case Repo.query!(
           "SELECT geocoded,without_data FROM phoenix.stats_point_counts WHERE user_id=$1 AND computed_at>$2 AND COALESCE((SELECT value FROM phoenix.cursors WHERE key=$3),'')=$4",
           [
             user.id,
             DateTime.add(period.now, -86400),
             "stats_point_counts:#{user.id}",
             generation
           ], log: false).rows do
      [[geocoded, without_data]] ->
        %{
          state: :ready,
          total: user.points_count || 0,
          geocoded: geocoded,
          without_data: if(Keyword.get(opts, :store_geodata, true), do: without_data),
          percentage:
            if(user.points_count in [nil, 0],
              do: 0.0,
              else: min(RubyFloat.round(geocoded * 100.0 / user.points_count, 1), 100.0)
            )
        }

      _ ->
        %{
          state: :pending,
          total: user.points_count || 0,
          geocoded: nil,
          without_data: nil,
          percentage: nil
        }
    end
  end

  defp distances(stats),
    do: for(month <- 1..12, do: Enum.find_value(stats, 0, &(&1.month == month and &1.distance)))
end
