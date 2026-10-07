defmodule DawarichWeb.Api.Params do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2]

  alias Dawarich.Distance
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @stamp ~r/\A(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,6})?)?(?:Z|[+-](\d{2}):(\d{2})))?\z/
  @http ~r/\A(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun), (\d{2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT\z/
  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
  @coordinate ~r/\A-?\d{1,3}(?:\.\d{1,20})?(?:e-\d{1,2})?\z/
  @count ~r/\A\d{1,9}\z/
  @date ~r/\A(\d{4})-(\d{2})-(\d{2})\z/

  def year(nil), do: {:ok, nil}
  def year(value) when is_integer(value) and value in 1970..2037, do: {:ok, value}

  def year(value) when is_binary(value) do
    with true <- value =~ ~r/\A\d{4}\z/,
         year when year in 1970..2037 <- String.to_integer(value) do
      {:ok, year}
    else
      _ -> {:replay, "year parameter #{inspect(value)}"}
    end
  end

  def year(value), do: {:replay, "year parameter #{inspect(value)}"}

  def unit(param, settings) do
    settings = Dawarich.UserSettings.safe(settings)

    chosen =
      cond do
        is_binary(param) and Ruby.present?(param) -> {:ok, param}
        is_nil(param) or is_binary(param) -> setting_unit(settings)
        true -> {:replay, "distance_unit parameter #{inspect(param)}"}
      end

    case chosen do
      {:ok, unit} when is_binary(unit) ->
        if Distance.unit?(unit),
          do: {:ok, unit},
          else: {:replay, "distance unit #{inspect(unit)}"}

      {:ok, unit} ->
        {:replay, "distance unit #{inspect(unit)}"}

      replay ->
        replay
    end
  end

  def min_minutes(settings),
    do: minutes(Dawarich.UserSettings.safe(settings)["min_minutes_spent_in_city"])

  def timestamp(value) when is_binary(value) do
    cond do
      value =~ ~r/\A\d+\z/ -> {:ok, {:epoch, String.to_integer(value)}}
      stamp?(value) -> {:ok, {:text, value}}
      true -> {:replay, "timestamp #{inspect(value)}"}
    end
  end

  def timestamp(value), do: {:replay, "timestamp #{inspect(value)}"}

  def flight_filter(start_at, end_at) do
    if Ruby.blank?(start_at) and Ruby.blank?(end_at),
      do: {:ok, :none},
      else:
        with(
          {:ok, from} <- flight_time(start_at),
          {:ok, to} <- flight_time(end_at),
          do: {:ok, {from, to}}
        )
  end

  def missing(params, names), do: Enum.filter(names, &Ruby.blank?(params[&1]))

  def if_modified_since(conn) do
    case get_req_header(conn, "if-modified-since") do
      [] -> {:ok, nil}
      [value] -> http(String.replace(value, ~r/\A[ \t]+|[ \t]+\z/, ""))
      _ -> {:replay, "several If-Modified-Since headers"}
    end
  end

  def http_date(%NaiveDateTime{} = at), do: Calendar.strftime(at, "%a, %d %b %Y %H:%M:%S GMT")

  def coordinates(lat, lon) do
    cond do
      not (text?(lat) and text?(lon)) -> {:replay, "coordinate parameter shape"}
      Ruby.blank?(lat) or Ruby.blank?(lon) -> :missing
      lat =~ @coordinate and lon =~ @coordinate -> {:ok, Ruby.to_f(lat), Ruby.to_f(lon)}
      true -> {:replay, "coordinate parameter shape"}
    end
  end

  def count(nil, default), do: {:ok, default}

  def count(value, _default) when is_binary(value) do
    if value =~ @count,
      do: {:ok, String.to_integer(value)},
      else: {:replay, "count parameter shape"}
  end

  def count(_value, _default), do: {:replay, "count parameter shape"}

  def date(value) do
    cond do
      is_nil(value) or (is_binary(value) and Ruby.blank?(value)) -> {:ok, nil}
      is_binary(value) -> calendar(Regex.run(@date, value, capture: :all_but_first))
      true -> {:replay, "date parameter shape"}
    end
  end

  def text(value) when is_nil(value) or is_binary(value), do: {:ok, value}
  def text(_value), do: {:replay, "text parameter shape"}

  defp text?(value), do: is_nil(value) or is_binary(value)

  defp calendar([y, m, d]) do
    case Date.new(String.to_integer(y), String.to_integer(m), String.to_integer(d)) do
      {:ok, %Date{year: year} = date} when year in 1970..2037 -> {:ok, date}
      _ -> {:replay, "date parameter shape"}
    end
  end

  defp calendar(nil), do: {:replay, "date parameter shape"}

  defp setting_unit(%{"maps" => maps}) when is_map(maps), do: {:ok, maps["distance_unit"] || "km"}
  defp setting_unit(%{"maps" => nil}), do: {:ok, "km"}
  defp setting_unit(%{"maps" => other}), do: {:replay, "maps setting #{inspect(other)}"}
  defp setting_unit(_settings), do: {:ok, "km"}

  defp minutes(value) when value in [nil, false], do: {:ok, 60}
  defp minutes(value) when is_integer(value), do: {:ok, value}
  defp minutes(value) when is_float(value), do: {:ok, trunc(value)}

  defp minutes(value) when is_binary(value),
    do:
      if(value =~ ~r/\A\d+\z/,
        do: {:ok, String.to_integer(value)},
        else: {:replay, "min_minutes_spent_in_city #{inspect(value)}"}
      )

  defp minutes(value), do: {:replay, "min_minutes_spent_in_city #{inspect(value)}"}

  defp flight_time(value) do
    cond do
      Ruby.blank?(value) -> {:ok, nil}
      is_binary(value) and stamp?(value) -> {:ok, value}
      true -> {:replay, "flight time #{inspect(value)}"}
    end
  end

  defp stamp?(text) do
    case Regex.run(@stamp, text, capture: :all_but_first) do
      nil ->
        false

      parts ->
        [y, m, d, hh, mi, ss, oh, om] =
          Enum.map(parts ++ List.duplicate("", 8 - length(parts)), &number/1)

        match?({:ok, _}, Date.new(y, m, d)) and hh <= 23 and mi <= 59 and ss <= 59 and oh <= 14 and
          om <= 59
    end
  end

  defp number(""), do: 0
  defp number(digits), do: String.to_integer(digits)

  defp http(value) do
    with [d, mon, y, h, mi, s] <- Regex.run(@http, value, capture: :all_but_first),
         {:ok, at} <-
           NaiveDateTime.new(
             String.to_integer(y),
             Enum.find_index(@months, &(&1 == mon)) + 1,
             String.to_integer(d),
             String.to_integer(h),
             String.to_integer(mi),
             String.to_integer(s)
           ) do
      {:ok, at}
    else
      _ -> {:replay, "If-Modified-Since #{inspect(value)}"}
    end
  end
end
