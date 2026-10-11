defmodule Dawarich.Analytics.Period do
  @moduledoc false
  alias Dawarich.{RubyInteger, Stats, UserSettings, Distance}
  alias Dawarich.Accounts.DataAccess

  def admit(scope, params, kind, opts, available \\ []) do
    with {:ok, scope} <- DataAccess.admit(scope, settings: true),
         true <-
           is_map(params) and
             Enum.all?(params, fn {_k, v} ->
               is_nil(v) or (is_binary(v) and byte_size(v) <= 128)
             end) do
      now = Keyword.get(opts, :now, DateTime.utc_now())

      hosted =
        Keyword.get(opts, :self_hosted, Dawarich.ReleaseMigration.self_hosted?(System.get_env()))

      context = Stats.context(scope.user, now, hosted)
      unit = unit(UserSettings.get(scope.user))
      raw = params["year"] || to_string(List.first(available) || context.today.year)
      year = if raw == "all" and kind == :insights, do: nil, else: RubyInteger.to_i(raw)
      month = if params["month"], do: RubyInteger.to_i(params["month"])

      with true <- Distance.unit?(unit) and (is_nil(year) or abs(year) <= 9999),
           true <- kind != :month or month in 1..12 do
        {:ok, scope,
         Map.merge(context, %{
           year: year,
           month: month,
           unit: unit,
           all_time: is_nil(year),
           page: max(1, min(RubyInteger.to_i(params["page"] || "1"), 1_000_000_000_000)),
           now: now,
           self_hosted: hosted
         })}
      else
        _ -> {:error, :invalid_input}
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_input}
    end
  rescue
    _ -> {:error, :invalid_input}
  end

  def unit(settings) do
    case UserSettings.safe(settings)["maps"] do
      %{"distance_unit" => unit} when unit not in [nil, false] -> to_string(unit)
      _ -> "km"
    end
  end

  def rounded(nil, _), do: 0
  def rounded(meters, unit), do: round(Distance.convert(meters, unit))

  def narrow(toponyms),
    do:
      Enum.map(Dawarich.Stats.Toponyms.sanitize(toponyms), fn value ->
        %{
          "country" => value["country"],
          "cities" => Enum.map(value["cities"], &Map.take(&1, ["city"]))
        }
      end)
end
