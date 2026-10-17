defmodule Dawarich.ReleaseOperations.AnomaliesTest do
  use Dawarich.JobsCase

  alias Dawarich.RecalculationFixtures, as: Fixtures
  alias Dawarich.ReleaseOperations, as: Ops
  alias Dawarich.ReleaseOperations.{Anomalies, AnomalyClaims}

  @now ~U[2026-10-03 12:00:00Z]

  setup do
    start_oban(:anomaly_dispatcher)
    :ok
  end

  test "failed fanout rolls back claims and lost claim race requests another pass" do
    Fixtures.load!(ScratchRepo, Fixtures.case!("dispatch_disabled"))
    original = rows("SELECT id,settings FROM users ORDER BY id")
    flags = rows("SELECT id,anomaly FROM points ORDER BY id")
    args = args()

    assert_raise RuntimeError, "fanout", fn ->
      run(args, after_child: fn _ -> raise "fanout" end)
    end

    assert rows("SELECT id,settings FROM users ORDER BY id") == original
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert run(args) == :ok
    assert run(args) == :ok
    assert rows("SELECT id,anomaly FROM points ORDER BY id") == flags

    assert rows("SELECT count(*) FROM users WHERE settings ? 'anomaly_rules_recalculated_at'") ==
             [[4]]

    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[2]]

    for [child] <- rows("SELECT args FROM oban.oban_jobs") do
      request = child["cursor"]["request"]
      assert request["user_id"] in [170_105, 170_106]
      assert request["attempt"] == 1
      assert request["ambient_zone"] == "Europe/Berlin"
      assert {:ok, _} = Ecto.UUID.cast(request["source_job_id"])
    end

    reset!(ScratchRepo)
    Fixtures.load!(ScratchRepo, Fixtures.case!("dispatch_disabled"))
    lost = fn ids -> assert Enum.sort(AnomalyClaims.claim(ScratchRepo, ids, @now)) == ids end
    assert run(args, after_scan: lost) == :ok
    assert [[next]] = rows("SELECT args FROM oban.oban_jobs")

    assert next["cursor"]["request"]["source_job_id"] ==
             args["cursor"]["request"]["source_job_id"]

    assert next["cursor"]["pass"] == 1
    assert run(args) == :ok
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
    assert run(next) == :ok
    assert rows("SELECT status FROM phoenix.release_operations") == [["completed"]]
  end

  defp args do
    id = Ecto.UUID.generate()

    {:ok, decoded} =
      Anomalies.args_from_command(1, %{
        "limit" => 2,
        "source_job_id" => id,
        "ambient_zone" => "Europe/Berlin"
      })

    Map.put(decoded, "event_id", id)
  end

  defp run(args, opts \\ []),
    do:
      Ops.run(
        ScratchRepo,
        :anomaly_dispatcher,
        Anomalies,
        %Oban.Job{args: args, attempt: 1, max_attempts: 26},
        Keyword.put(opts, :now, @now)
      )
end
