defmodule Dawarich.MapApi.Params do
  @moduledoc false

  alias Dawarich.{RubyInteger, SafeTimestamp}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.Api.Params

  @false_values ["0", "f", "F", "false", "FALSE", "off", "OFF"]

  def boolean(value) when value in [nil, ""], do: false
  def boolean(value), do: value not in @false_values

  def safe_range(start_value, end_value, now) do
    with {:ok, from} <- stamp(start_value),
         {:ok, to} <- stamp(end_value),
         do: {:ok, SafeTimestamp.range(from, to, now)}
  end

  def zoned_time(value) do
    case stamp(value) do
      {:ok, {:text, text}} -> {:ok, text}
      {:ok, _other} -> {:replay, "track time #{inspect(value)}"}
      replay -> replay
    end
  end

  def bbox(values) do
    with [min_lng, max_lng, min_lat, max_lat] = floats <- Enum.map(values, &Ruby.float/1),
         true <- Enum.all?(floats, &is_float/1),
         true <- min_lng <= max_lng and min_lat <= max_lat,
         true <- min_lng >= -180 and max_lng <= 180 and min_lat >= -90 and max_lat <= 90 do
      {:ok, [min_lng, min_lat, max_lng, max_lat]}
    else
      _ -> :error
    end
  end

  def page(value), do: max(RubyInteger.to_i(value), 1)

  def per_page(value, default) do
    case RubyInteger.to_i(value) do
      number when number > 0 -> number
      _ -> default
    end
  end

  def track_per_page(value),
    do:
      if(Ruby.present?(value), do: value |> RubyInteger.to_i() |> max(1) |> min(1000), else: 1000)

  defp stamp(nil), do: {:ok, nil}
  defp stamp({:now, now}), do: {:ok, {:epoch, DateTime.to_unix(now)}}
  defp stamp(value), do: if(Ruby.blank?(value), do: {:ok, nil}, else: Params.timestamp(value))
end
