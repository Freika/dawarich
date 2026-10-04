defmodule Dawarich.ImportsContractTest do
  use ExUnit.Case, async: true

  alias Dawarich.Jobs.Registry

  @fixture Path.expand("../fixtures/wave4/commands.json", __DIR__)
  @imports ~w(
    command:imports.airtrail_flights
    command:imports.destroy
    command:imports.prepare_download
    command:imports.process_gpx
    command:imports.process_normal
    command:imports.update_points_count
  )

  test "Imports registers exactly its six canonical command keys, unclaimable" do
    entries = Enum.filter(Registry.entries(), &String.starts_with?(&1.key, "command:imports."))
    assert Enum.map(entries, & &1.key) |> Enum.sort() == Enum.sort(@imports)
    assert Enum.all?(entries, &(&1.kind == :command and &1.claimable == false))
  end

  test "original wave 4 workers still decode exactly the payload Rails produces" do
    for {type, %{"version" => version, "payload" => payload}} <-
          @fixture |> File.read!() |> Jason.decode!() do
      assert {:ok, worker} = Registry.command(type)
      assert worker.args_from_command(version, payload) == {:ok, payload}

      assert worker.args_from_command(version, Map.put(payload, "extra", 1)) ==
               {:error, "invalid_payload"}
    end
  end
end
