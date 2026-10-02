defmodule Dawarich.Imports.DatePartsTest do
  use ExUnit.Case, async: true
  alias Dawarich.Imports.DateParts
  @oracle Path.expand("../../fixtures/gpx/rails_preparation_oracle.json", __DIR__)
  @cases @oracle
         |> File.read!()
         |> Jason.decode!()
         |> Map.fetch!("time_cases")
         |> Enum.uniq_by(& &1["text"])

  for example <- @cases do
    @example example
    test "actual Ruby Date._parse(false) #{example["text"]}" do
      if @example["parts_error"] do
        assert_raise ArgumentError, fn -> DateParts.parse(@example["text"]) end
      else
        assert DateParts.parse(@example["text"]) == @example["parts"]
      end
    end
  end
end
