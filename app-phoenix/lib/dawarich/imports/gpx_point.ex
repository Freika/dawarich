defmodule Dawarich.Imports.GpxPoint do
  @moduledoc false
  alias Dawarich.Imports.ImportTime
  alias Dawarich.Ingest.{Ruby, Unsupported}
  alias Dawarich.RubyFloat
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: Support

  @decimal ~r/\A[\x09-\x0D ]*([+-]?)(\d+(?:_\d+)*)?(?:\.(\d+(?:_\d+)*|))?(?:[eEdD]([+-]?\d+(?:_\d+)*))?/

  def prepare(point, tracker, import, context) do
    if Enum.any?(~w(lat lon time), &Ruby.blank?(point[&1])) do
      nil
    else
      altitude = number(point["ele"])
      lonlat = "POINT(#{coordinate(point["lon"])} #{coordinate(point["lat"])})"
      timestamp = ImportTime.parse(point["time"], context.zone, clock(context.now), context.repo)
      if is_nil(timestamp), do: raise(ArgumentError, "undefined method 'utc' for nil")

      attrs = %{
        lonlat: lonlat,
        altitude: altitude,
        timestamp: timestamp,
        tracker_id: tracker,
        import_id: import.id,
        user_id: import.user_id,
        velocity: speed(point["extensions"]),
        created_at: naive(clock(context.now)),
        updated_at: naive(clock(context.now))
      }

      if context.altitude_decimal?, do: Map.put(attrs, :altitude_decimal, altitude), else: attrs
    end
  end

  defp coordinate(value) when is_binary(value) do
    case String.trim(value) do
      special when special in ["NaN", "Infinity", "+Infinity", "-Infinity"] ->
        String.trim_leading(special, "+")

      _ ->
        groups = Regex.run(@decimal, value, capture: :all_but_first) || []
        [sign, int, frac, exp] = groups ++ List.duplicate("", 4 - length(groups))
        fraction = String.replace(frac, "_", "")

        decimal =
          %Decimal{
            coef: String.to_integer(digits(int) <> fraction),
            sign: if(sign == "-", do: -1, else: 1),
            exp: String.to_integer(digits(exp)) - byte_size(fraction)
          }
          |> normalize()

        if byte_size(Integer.to_string(decimal.coef)) + abs(decimal.exp) + 8 > 1_048_576,
          do: raise(ArgumentError, "coordinate expansion exceeds GPX point budget")

        text = Decimal.to_string(decimal, :normal, max_digits: 1_048_576)
        if String.contains?(text, "."), do: text, else: text <> ".0"
    end
  end

  defp coordinate(_value), do: raise(ArgumentError, "coordinate must be a string")

  defp digits(""), do: "0"
  defp digits(value), do: String.replace(value, "_", "")

  defp normalize(%Decimal{coef: 0} = decimal), do: %{decimal | exp: 0}

  defp normalize(decimal) do
    original = Integer.to_string(decimal.coef)
    shortened = String.trim_trailing(original, "0")

    %{
      decimal
      | coef: String.to_integer(shortened),
        exp: decimal.exp + byte_size(original) - byte_size(shortened)
    }
  end

  defp speed(extensions) do
    if Ruby.blank?(extensions) do
      nil
    else
      unless is_map(extensions), do: raise(ArgumentError, "extensions does not have dig method")
      nested = extensions["TrackPointExtension"]
      direct = extensions["speed"]
      value = if Ruby.truthy?(direct), do: direct, else: if(is_map(nested), do: nested["speed"])
      if is_nil(value), do: nil, else: rounded(number(value))
    end
  end

  defp rounded(special) when special in [:infinity, :neg_infinity], do: special
  defp rounded(value), do: RubyFloat.round(value, 1)
  defp number(value) when is_binary(value), do: Support.to_f(value)

  defp number(value) do
    Ruby.to_f(value)
  rescue
    e in Unsupported -> raise ArgumentError, Exception.message(e)
  end

  defp clock(fun) when is_function(fun, 0), do: fun.()
  defp clock(now), do: now
  defp naive(%DateTime{} = now), do: DateTime.to_naive(now)
  defp naive(%NaiveDateTime{} = now), do: now
end
