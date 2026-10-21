defmodule Dawarich.Build.NativeM5RegisterTest do
  use ExUnit.Case, async: true

  test "integrated trips differences name behaviour successors and the upload sweep boundary" do
    register = File.read!("parity/expected_diffs.md")

    for {id, successor} <- [
          {"ED-NATIVE-M5-EDITOR", "a new foreign upload cannot be attached by another actor"},
          {"ED-NATIVE-M5-TRIPS-OWNERSHIP",
           "trip form rejects stale identity and foreign id before save"},
          {"ED-NATIVE-M5-TRIPS-DURABLE-READS",
           "trip initial and connected renders request one calculation for an input revision"},
          {"ED-NATIVE-M5-TRIPS-BOUNDS",
           "day windows stay bounded, continue by cursor and carry their dated notes"}
        ] do
      row = register |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "| #{id} |"))
      assert is_binary(row), id
      assert String.contains?(row, successor), id
    end

    assert register =~ "B3-FU-RICH-UPLOAD-SWEEP"
    assert register =~ "FRB-NATIVE-M5-FAMILY-INDICATOR"
  end

  test "broken public achievement state records the locale and session decision" do
    register = File.read!("parity/expected_diffs.md")

    row =
      register
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, "| ED-NATIVE-M5-PUBLIC-CARD-BROKEN-STATE |"))

    assert is_binary(row)

    for text <- [
          "503",
          "no locale/session effects",
          "application_controller.rb:184-190",
          "a10c_ownership_test"
        ],
        do: assert(String.contains?(row, text))
  end

  test "cold Insights weekly differences retain the completed-read witness and source cause" do
    register = File.read!("parity/expected_diffs.md")

    row =
      register
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, "| ED-E1-INSIGHTS-COLD-WEEKLY |"))

    assert is_binary(row)

    for text <- [
          "load_yearly_patterns",
          "load_monthly_digest",
          "insights_controller.rb:41-42",
          "reconnect reads a finished refresh without generating again"
        ],
        do: assert(String.contains?(row, text))

    visual = File.read!("../docs/phoenix/visual-parity-divergences.md")
    assert visual =~ "ED-E1-INSIGHTS-COLD-WEEKLY"
  end
end
