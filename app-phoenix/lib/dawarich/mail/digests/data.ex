defmodule Dawarich.Mail.Digests.Data do
  @moduledoc false

  alias Dawarich.{RubyFloat, RubyInteger}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @units %{"km" => 1000, "mi" => 1609.34, "m" => 1, "ft" => 0.3048, "yd" => 0.9144}
  @load """
  SELECT u.id, u.email, u.settings, u.created_at, u.deleted_at, row_to_json(d)
  FROM public.digests d JOIN public.users u ON u.id = d.user_id
  WHERE d.user_id = $1 AND d.period_type = $2 AND d.year = $3 AND ($2 = 1 OR d.month = $4)
  ORDER BY d.id LIMIT 1
  """
  @stats "SELECT year, month, daily_distance FROM public.stats WHERE user_id = $1 AND year = $2 ORDER BY id"

  def fetch(repo, user_id, period, year, month \\ nil) do
    case load(repo, user_id, period, year, month) do
      nil ->
        nil

      %{user: user, digest: digest} = records ->
        Map.put(records, :projection, project(repo, user, digest))
    end
  end

  def load(repo, user_id, period, year, month \\ nil) do
    kind = if period in [:monthly, "monthly"], do: 0, else: 1

    case repo.query!(@load, [user_id, kind, year, month], log: false).rows do
      [] ->
        nil

      [[id, email, settings, created_at, deleted_at, digest]] ->
        user = %{
          id: id,
          email: email,
          settings: settings,
          created_at: created_at,
          deleted_at: deleted_at
        }

        digest = Map.put(digest, "period_type", if(kind == 0, do: "monthly", else: "yearly"))
        %{user: user, digest: digest}
    end
  end

  def delivery(repo, user_id, digest_id) do
    case repo.query!(
           "SELECT u.id, u.email, u.settings, row_to_json(d) FROM public.users u JOIN public.digests d ON d.user_id=u.id WHERE u.id=$1 AND d.id=$2",
           [user_id, digest_id],
           log: false
         ).rows do
      [[id, email, settings, digest]] ->
        kind = if digest["period_type"] == 0, do: "monthly", else: "yearly"

        %{
          user: %{id: id, email: email, settings: settings},
          digest: Map.put(digest, "period_type", kind)
        }

      [] ->
        nil
    end
  end

  def project(repo, user, digest) do
    unit = distance_unit(Dawarich.UserSettings.get(user))

    distances =
      Map.new(object(digest["monthly_distances"]), fn {key, value} ->
        {to_string(key), convert_distance(value, unit)}
      end)

    locations = object(digest["time_spent_by_location"])
    countries = significant(locations["countries"])

    if digest["period_type"] == "monthly" do
      visits = object(digest["first_time_visits"])

      %{
        "distance_unit" => unit,
        "daily_distances" => distances,
        "weekday_totals" => weekdays(distances, digest["year"], digest["month"]),
        "active_days" => Enum.count(distances, fn {_day, distance} -> distance > 0 end),
        "top_countries" => countries,
        "top_cities" => significant(locations["cities"]),
        "first_countries" => array(visits["countries"]),
        "first_cities" => array(visits["cities"]),
        "daily_values" => nil,
        "monthly_distances" => nil
      }
    else
      %{
        "distance_unit" => unit,
        "daily_distances" => nil,
        "weekday_totals" => nil,
        "active_days" => nil,
        "top_countries" => countries,
        "top_cities" => nil,
        "first_countries" => nil,
        "first_cities" => nil,
        "daily_values" => yearly(repo, user.id, digest["year"], unit),
        "monthly_distances" => distances
      }
    end
  end

  def convert_distance(value, unit) do
    if Ruby.blank?(value), do: 0.0, else: number(value) / Map.fetch!(@units, unit)
  end

  def number(nil), do: 0.0
  def number(value) when is_number(value), do: value * 1.0
  def number(value) when is_binary(value), do: Ruby.to_f(value)
  def number(_), do: raise(ArgumentError, "invalid numeric mail value")

  def object(nil), do: %{}
  def object(value) when is_map(value), do: value

  def object(value) when is_list(value) do
    Map.new(value, fn
      [key, item] -> {key, item}
      {key, item} -> {key, item}
      _ -> raise(ArgumentError, "invalid digest pair")
    end)
  end

  def object(_), do: raise(ArgumentError, "invalid digest object")

  def array(nil), do: []
  def array(value) when is_list(value), do: value
  def array(value) when is_map(value), do: Map.to_list(value)
  def array(_), do: raise(ArgumentError, "invalid digest array")

  defp distance_unit(settings) do
    settings = Dawarich.UserSettings.safe(settings)
    maps = object(settings["maps"])
    maps["distance_unit"] || "km"
  end

  defp significant(entries) do
    Enum.filter(array(entries), fn entry ->
      RubyInteger.to_i(Ruby.index(entry, "minutes")) > 60
    end)
  end

  defp weekdays(distances, year, month) do
    totals =
      Enum.reduce(distances, List.duplicate(0.0, 7), fn {day, distance}, acc ->
        case date(year, month, day) do
          {:ok, date} -> List.update_at(acc, Date.day_of_week(date) - 1, &(&1 + distance))
          {:error, _} -> acc
        end
      end)

    Enum.map(totals, &RubyFloat.round/1)
  end

  defp yearly(repo, user_id, year, unit) do
    Enum.reduce(repo.query!(@stats, [user_id, year], log: false).rows, %{}, fn [
                                                                                 year,
                                                                                 month,
                                                                                 daily
                                                                               ],
                                                                               acc ->
      Enum.reduce(object(daily), acc, fn {day, distance}, values ->
        case date(year, month, day) do
          {:ok, date} -> Map.put(values, Date.to_iso8601(date), convert_distance(distance, unit))
          {:error, _} -> values
        end
      end)
    end)
  end

  defp date(year, month, day) do
    day = RubyInteger.to_i(day)

    with {:ok, first} <- Date.new(year, month, 1) do
      day = if day < 0, do: Date.days_in_month(first) + day + 1, else: day
      Date.new(year, month, day)
    end
  end
end
