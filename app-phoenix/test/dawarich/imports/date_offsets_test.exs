defmodule Dawarich.Imports.DateOffsetsTest do
  use ExUnit.Case, async: true
  alias Dawarich.Imports.DateParts
  @oracle Path.expand("../../fixtures/gpx/rails_preparation_oracle.json", __DIR__)
  @cases @oracle |> File.read!() |> Jason.decode!() |> Map.fetch!("offset_cases")

  test "actual Ruby fixed-zone offset names used by loose date parsing" do
    for example <- @cases do
      assert DateParts.parse("12:30:00 " <> example["name"])["offset"] == example["offset"],
             inspect(example)
    end
  end
end
