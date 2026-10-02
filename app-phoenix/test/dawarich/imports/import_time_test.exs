defmodule Dawarich.Imports.ImportTimeTest do
  use Dawarich.IngestCase, async: false
  alias Dawarich.Imports.ImportTime
  @oracle Path.expand("../../fixtures/gpx/rails_preparation_oracle.json", __DIR__)
  @cases @oracle
         |> File.read!()
         |> Jason.decode!()
         |> Map.fetch!("time_cases")
         |> Enum.group_by(& &1["zone"])
  @now ~U[2026-01-15 23:30:00Z]

  test "Ruby fractional offset rounding ignores digits beyond the rounding digit" do
    assert ImportTime.parse("2024-01-01 12:30:00.444 +5.12345665001", "UTC", @now, Repo) ==
             1_704_093_756
  end

  for {zone, examples} <- @cases do
    @zone zone
    @examples examples
    test "actual Rails Time.zone.parse under #{zone}" do
      mismatches =
        Enum.flat_map(@examples, fn example ->
          expected = if example["error"], do: :invalid, else: {:ok, example["epoch"]}

          actual =
            try do
              {:ok, ImportTime.parse(example["text"], @zone, @now, Repo)}
            rescue
              ArgumentError -> :invalid
            end

          if actual == expected, do: [], else: [{example["text"], expected, actual}]
        end)

      assert mismatches == []
    end
  end
end
