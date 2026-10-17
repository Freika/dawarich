defmodule Dawarich.Imports.GooglePhonePointsTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.{GooglePhone.Points, ImportTime}
  @dir Path.expand("../../fixtures/imports/formats", __DIR__)

  test "phone semantic raw and array points match Rails" do
    for path <- Path.wildcard(Path.join(@dir, "phone_points_*.json")),
        not String.contains?(path, "metadata_") do
      assert_case(path)
    end
  end

  test "phone activity metadata preserves Rails coercion" do
    for path <- Path.wildcard(Path.join(@dir, "phone_points_*.json")),
        String.contains?(path, "metadata_") or String.ends_with?(path, "semantic.json") do
      assert_case(path)
    end
  end

  defp assert_case(path) do
    expected = path |> File.read!() |> Jason.decode!()

    import = %{
      id: expected["identities"]["import_id"],
      user_id: expected["identities"]["user_id"]
    }

    context = %{
      repo: ScratchRepo,
      now: ~U[2026-01-15 23:30:00Z],
      zone: expected["zone"],
      altitude_decimal?: not expected["legacy"]
    }

    section =
      %{
        "semantic_segment" => :semantic_segment,
        "raw_signal" => :raw_signal,
        "raw_array" => :raw_array
      }[expected["section"]]

    if expected["error"] do
      assert_raise ArgumentError, fn ->
        Enum.flat_map(expected["input"], &Points.prepare(section, &1, import, context))
      end
    else
      {batches, _} =
        Enum.map_reduce(expected["input"], %{assigned: %{}, used: MapSet.new()}, fn value,
                                                                                    state ->
          Points.prepare(section, value, import, context, state)
        end)

      actual = List.flatten(batches)
      assert normalize(actual, context) == normalize(expected["prepared_points"], context), path
    end
  end

  defp normalize(points, context) do
    Enum.map(points, fn point ->
      Map.new(point, fn {key, value} ->
        key = to_string(key)

        value =
          cond do
            key in ["created_at", "updated_at"] and is_binary(value) ->
              ImportTime.parse(value, "Etc/UTC", context.now, ScratchRepo)

            key in ["created_at", "updated_at"] ->
              value |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

            key == "altitude_decimal" and not is_nil(value) ->
              value |> decimal() |> Decimal.normalize() |> Decimal.to_string(:normal)

            true ->
              value
          end

        {key, value}
      end)
    end)
  end

  defp decimal(%Decimal{} = value), do: value
  defp decimal(value), do: Decimal.new(value)
end
