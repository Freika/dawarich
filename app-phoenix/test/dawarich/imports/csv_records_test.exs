defmodule Dawarich.Imports.CsvRecordsTest do
  use ExUnit.Case, async: true
  alias Dawarich.Imports.Csv.{Detector, Records}
  @dir Path.expand("../../fixtures/imports/formats", __DIR__)

  test "csv lexical fields preserve quotes nil and empty values" do
    for row <- corpus(), is_nil(row["error"]) do
      if row["kind"] == "records" do
        assert Records.parse(row["line"], row["delimiter"]) == row["fields"], row["name"]
      else
        actual = Detector.call(Path.join(@dir, row["input"]))
        assert normalize(actual) == row["detection"], row["name"]
      end
    end
  end

  test "csv rejects an unclosed physical quoted record" do
    for row <- corpus(), row["error"] do
      error =
        if row["kind"] == "records" do
          assert_raise Records.Error, fn -> Records.parse(row["line"], row["delimiter"]) end
        else
          assert_raise Detector.Error, fn -> Detector.call(Path.join(@dir, row["input"])) end
        end

      assert error.message == row["error"]["message"], row["name"]
      assert error.rails_class == row["error"]["class"], row["name"]
    end
  end

  defp normalize(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), normalize(v)} end)

  defp normalize(value) when is_atom(value) and value not in [nil, true, false],
    do: Atom.to_string(value)

  defp normalize(value), do: value
  defp corpus, do: @dir |> Path.join("csv_lexical.json") |> File.read!() |> Jason.decode!()
end
