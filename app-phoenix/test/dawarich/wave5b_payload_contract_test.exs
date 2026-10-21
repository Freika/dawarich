defmodule Dawarich.Wave5bPayloadContractTest do
  use ExUnit.Case, async: true

  alias Dawarich.Jobs.Registry

  @payloads Path.expand("../fixtures/wave5b/payloads.json", __DIR__)

  test "every Rails router payload decodes in Phoenix" do
    rows = @payloads |> File.read!() |> Jason.decode!()

    for %{"type" => type, "payload" => payload} <- rows do
      assert {:ok, worker} = Registry.command(type), type
      assert {:ok, _args} = worker.args_from_command(1, payload), type
    end

    point_batches =
      for %{"type" => "geocoding.reverse_point", "payload" => %{"point_ids" => ids}} <- rows,
          do: length(ids)

    assert Enum.sort(point_batches) == [1, 100]
  end
end
