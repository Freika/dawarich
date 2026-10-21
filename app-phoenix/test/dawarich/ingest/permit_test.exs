defmodule Dawarich.Ingest.PermitTest do
  use ExUnit.Case, async: true

  alias Dawarich.Ingest.{Permit, Unsupported}

  @units "test/fixtures/ingest/units.json" |> File.read!() |> Jason.decode!()

  defp munge(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, munge(v)} end)
  defp munge(list) when is_list(list), do: for(e <- list, e != nil, do: munge(e))
  defp munge(value), do: value

  test "permits exactly what Rails permits for each endpoint's filter" do
    Code.ensure_loaded!(Permit)

    for %{"endpoint" => endpoint, "input" => input, "permit" => expected} <- @units["params"] do
      result =
        try do
          %{
            "ok" =>
              apply(Permit, String.to_existing_atom(endpoint_filter(endpoint)), [munge(input)])
          }
        rescue
          Unsupported -> :unsupported
        end

      case result do
        :unsupported -> assert Map.has_key?(input, "locations"), inspect(input)
        permitted -> assert permitted == expected, "#{endpoint}: #{inspect(input)}"
      end
    end
  end

  defp endpoint_filter("points"), do: "geojson"
  defp endpoint_filter("overland"), do: "geojson"
  defp endpoint_filter(other), do: other
end
