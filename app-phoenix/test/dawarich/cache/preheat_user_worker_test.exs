defmodule Dawarich.Cache.PreheatUserWorkerTest do
  use Dawarich.JobsCase

  alias Dawarich.Cache.PreheatUserWorker, as: Worker
  alias Dawarich.DigestFixtures, as: F

  test "decodes only v1 user timezone and stable source job UUID and runs durable preheat" do
    payload = %{
      "user_id" => 14101,
      "time_zone" => "Europe/Berlin",
      "source_job_id" => Ecto.UUID.generate()
    }

    assert Worker.args_from_command(1, payload) == {:ok, payload}
    job = Worker.new(payload) |> Ecto.Changeset.apply_changes()
    assert job.args == payload
    assert job.queue == "projections"
    assert job.max_attempts == 3

    invalid = [
      Map.delete(payload, "source_job_id"),
      Map.put(payload, "source_job_id", nil),
      Map.put(payload, "source_job_id", "bad-uuid"),
      Map.put(payload, "source_job_id", "00000000-0000-4000-8000-00000000000z"),
      Map.put(payload, "source_job_id", 123),
      Map.put(payload, "user_id", "14101"),
      Map.put(payload, "user_id", 1.5),
      Map.put(payload, "time_zone", nil),
      Map.put(payload, "run_at", "2026-10-03T12:00:00Z"),
      Map.put(payload, "extra", false)
    ]

    for bad <- invalid do
      assert Worker.args_from_command(1, bad) == {:error, "invalid_payload"}
      assert Worker.run(ScratchRepo, bad) == {:error, "invalid_payload"}
    end

    for version <- [0, 2, "1"],
        do: assert(Worker.args_from_command(version, payload) == {:error, "unsupported_version"})

    assert [[0]] = rows("SELECT count(*) FROM digests")
    kase = F.case!("berlin_yearly")
    F.load!(ScratchRepo, kase)
    assert Worker.run(ScratchRepo, payload, Keyword.delete(F.options(kase), :uuid)) == :ok
    digest = Enum.find(F.digests(ScratchRepo, 14101), &(&1["year"] == 2025))
    assert digest["distance"] == hd(kase["expected"]["rows"])["distance"]
    assert digest["travel_patterns"] == hd(kase["expected"]["rows"])["travel_patterns"]
    assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")
    assert Worker.perform(%Oban.Job{args: payload}) == :ok
  end
end
