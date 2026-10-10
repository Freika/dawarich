defmodule Dawarich.Build.NativeM5RegisterTest do
  use ExUnit.Case, async: true

  test "integrated trips differences name behaviour successors and the upload sweep boundary" do
    register = File.read!("parity/expected_diffs.md")

    for {id, successor} <- [
          {"ED-NATIVE-M5-EDITOR", "a new foreign upload cannot be attached by another actor"},
          {"ED-NATIVE-M5-TRIPS-OWNERSHIP", "trip form rejects stale identity and foreign id before save"},
          {"ED-NATIVE-M5-TRIPS-DURABLE-READS", "trip initial and connected renders request one calculation for an input revision"},
          {"ED-NATIVE-M5-TRIPS-BOUNDS", "day windows stay bounded, continue by cursor and carry their dated notes"}
        ] do
      row = register |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "| #{id} |"))
      assert is_binary(row), id
      assert String.contains?(row, successor), id
    end

    assert register =~ "B3-FU-RICH-UPLOAD-SWEEP"
    assert register =~ "FRB-NATIVE-M5-FAMILY-INDICATOR"
  end
end
