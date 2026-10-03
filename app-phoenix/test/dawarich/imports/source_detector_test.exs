defmodule Dawarich.Imports.SourceDetectorTest do
  use ExUnit.Case, async: false
  alias Dawarich.Imports.SourceDetector
  @dir Path.expand("../../fixtures/imports/formats", __DIR__)

  test "detection keeps Rails precedence and raw fallback limits" do
    for row <- corpus(), not String.starts_with?(row["filename"], "mobile") do
      expected = if row["source"], do: String.to_atom(row["source"])

      assert SourceDetector.detect(Path.join(@dir, row["input"]), row["filename"]) == expected,
             row["filename"]
    end
  end

  test "mobile photo detection checks the format version" do
    for row <- corpus(), String.starts_with?(row["filename"], "mobile") do
      expected = if row["source"], do: String.to_atom(row["source"])

      assert SourceDetector.detect(Path.join(@dir, row["input"]), row["filename"]) == expected,
             row["filename"]
    end
  end

  defp corpus, do: @dir |> Path.join("source_detection.json") |> File.read!() |> Jason.decode!()
end
