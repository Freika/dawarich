defmodule Dawarich.Imports.GoogleRecordsPointTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.{JsonStream, GoogleRecords.DeviceTags, GoogleRecords.Point}
  alias Dawarich.Test.NormalFormats
  @dir Path.expand("../../fixtures/imports/formats", __DIR__)

  test "records point preparation preserves per-device metadata" do
    for path <- Path.wildcard(Path.join(@dir, "records_import_*.json")),
        not String.ends_with?(path, ".input.json") do
      expected = path |> File.read!() |> Jason.decode!()

      unless expected["preparation_error"] do
        import = %{
          id: expected["identities"]["import_id"],
          user_id: expected["identities"]["user_id"]
        }

        context = %{
          repo: ScratchRepo,
          zone: expected["zone"],
          now: ~N[2026-01-15 23:30:00],
          altitude_decimal?: expected["legacy"] != true
        }

        input = Path.join(@dir, expected["input"])

        points =
          JsonStream.reduce(
            input,
            [],
            fn
              {:value, [index, "locations"], point, _, _}, acc when is_integer(index) ->
                [Point.prepare(point, import, context) | acc]

              _, acc ->
                acc
            end,
            fn
              [index, "locations"] when is_integer(index) -> true
              _ -> false
            end,
            mode: :compat
          )

        actual =
          points
          |> Enum.reverse()
          |> Enum.map(fn p ->
            for {key, value} <- p,
                into: %{},
                do:
                  {to_string(key),
                   if(key in [:created_at, :updated_at],
                     do: value |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(),
                     else: value
                   )}
          end)
          |> Jason.encode!()
          |> Jason.decode!()

        expected =
          Enum.map(expected["prepared_points"], fn p ->
            for {key, value} <- p,
                into: %{},
                do:
                  {key,
                   if(key in ["created_at", "updated_at"],
                     do:
                       Dawarich.Imports.ImportTime.parse(
                         value,
                         "Etc/UTC",
                         ~U[2026-01-15 23:30:00Z]
                       ),
                     else: value
                   )}
          end)

        assert actual == expected
      end
    end
  end

  test "records device map sees declarations after locations" do
    for name <-
          ~w(records_import_valid records_import_late records_import_1001 records_import_none) do
      path = Path.join(@dir, name <> ".json")
      expected = path |> File.read!() |> Jason.decode!() |> NormalFormats.decode()

      actual =
        DeviceTags.reduce(Path.join(@dir, expected["input"]), [], fn tuple, acc ->
          [tuple | acc]
        end)

      assert Enum.reverse(actual) == expected["device_tags"]
    end
  end
end
