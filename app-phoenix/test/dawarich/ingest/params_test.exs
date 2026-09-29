defmodule Dawarich.Ingest.ParamsTest do
  use ExUnit.Case, async: true

  alias Dawarich.Ingest.{GeoJSON, OwnTracks, Timestamp, Traccar, Unsupported}

  @units "test/fixtures/ingest/units.json" |> File.read!() |> Jason.decode!()

  defp munge(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, munge(v)} end)
  defp munge(list) when is_list(list), do: for(e <- list, e != nil, do: munge(e))
  defp munge(value), do: value

  defp translate("points", params), do: GeoJSON.points(params, 1)
  defp translate("overland", params), do: GeoJSON.overland(params)
  defp translate("owntracks", params), do: OwnTracks.payloads(params)
  defp translate("traccar", params), do: Traccar.payloads(params)

  defp rails(%{"ok" => nil}), do: {:ok, []}
  defp rails(%{"ok" => list}) when is_list(list), do: {:ok, list}
  defp rails(%{"ok" => map}), do: {:ok, [map]}
  defp rails(%{"error" => "invalid_timestamp"}), do: :invalid
  defp rails(%{"error" => _}), do: :error

  test "payloads agree with the Rails Params classes" do
    for %{"endpoint" => endpoint, "own" => own, "input" => input, "payloads" => ruby} <-
          @units["params"] do
      phoenix =
        try do
          {:ok,
           endpoint
           |> translate(munge(input))
           |> Enum.map(&Map.new(&1, fn {k, v} -> {Atom.to_string(k), v} end))}
        rescue
          Timestamp.Invalid -> :invalid
          Unsupported -> :unsupported
        end

      case {phoenix, rails(ruby)} do
        {:unsupported, _} -> refute own, "#{endpoint} must own #{inspect(input)}"
        {result, expected} -> assert result == expected, "#{endpoint}: #{inspect(input)}"
      end
    end
  end
end
