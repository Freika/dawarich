defmodule Dawarich.Digests.JobArgsTest do
  use ExUnit.Case, async: true

  alias Dawarich.Digests.JobArgs

  test "digest arguments decode only exact v1 payloads and preserve ambient zone" do
    monthly = %{"user_id" => 42, "year" => 2025, "month" => 3, "time_zone" => "Tokyo"}
    yearly = Map.delete(monthly, "month")

    for {decoder, payload} <- [{:monthly, monthly}, {:yearly, yearly}] do
      assert apply(JobArgs, decoder, [1, payload]) == {:ok, payload}

      for key <- Map.keys(payload) do
        values = if key == "time_zone", do: [nil, 0, false, %{}], else: [nil, false, "1", 1.5]

        assert apply(JobArgs, decoder, [1, Map.delete(payload, key)]) ==
                 {:error, "invalid_payload"}

        for value <- values do
          assert apply(JobArgs, decoder, [1, Map.put(payload, key, value)]) ==
                   {:error, "invalid_payload"}
        end
      end

      for invalid <- [
            nil,
            [],
            %{},
            Map.put(payload, "event_id", "extra"),
            Map.put(payload, "run_at", 0)
          ] do
        assert apply(JobArgs, decoder, [1, invalid]) == {:error, "invalid_payload"}
      end

      for version <- [0, 2, "1", nil, 1.0] do
        assert apply(JobArgs, decoder, [version, payload]) == {:error, "unsupported_version"}
      end

      permissive = Map.merge(payload, %{"user_id" => -1, "year" => 0, "time_zone" => ""})
      permissive = if decoder == :monthly, do: Map.put(permissive, "month", 13), else: permissive
      assert apply(JobArgs, decoder, [1, permissive]) == {:ok, permissive}
    end
  end
end
