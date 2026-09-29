defmodule Dawarich.ImportsContractTest do
  use ExUnit.Case, async: true

  alias Dawarich.Jobs.Registry

  @fixture Path.expand("../fixtures/wave4/commands.json", __DIR__)
  @wave4 ["command:imports.update_points_count", "command:imports.airtrail_flights"]

  test "wave 4 registers exactly its two command keys, unclaimable" do
    entries = Enum.filter(Registry.entries(), &String.starts_with?(&1.key, "command:imports."))
    assert Enum.map(entries, & &1.key) |> Enum.sort() == Enum.sort(@wave4)
    assert Enum.all?(entries, &(&1.kind == :command and &1.claimable == false))
  end

  test "each worker decodes exactly the payload Rails produces" do
    for {type, %{"version" => version, "payload" => payload}} <-
          @fixture |> File.read!() |> Jason.decode!() do
      assert {:ok, worker} = Registry.command(type)
      assert worker.args_from_command(version, payload) == {:ok, payload}

      assert worker.args_from_command(version, Map.put(payload, "extra", 1)) ==
               {:error, "invalid_payload"}
    end
  end
end
