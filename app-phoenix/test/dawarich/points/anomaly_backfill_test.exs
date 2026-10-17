defmodule Dawarich.Points.AnomalyBackfillTest do
  use Dawarich.JobsCase

  alias Dawarich.RecalculationFixtures, as: Fixtures
  alias Dawarich.Points.AnomalyBackfill
  alias Dawarich.State

  setup do
    pool =
      start_supervised!({ScratchRepo, [name: nil, pool_size: 2, parameters: [timezone: "UTC"]]},
        id: :utc_backfill
      )

    ScratchRepo.put_dynamic_repo(pool)
    on_exit(fn -> ScratchRepo.put_dynamic_repo(ScratchRepo) end)
    :ok
  end

  test "resets once and resumes sorted source months with fenced effects" do
    source = Fixtures.case!("backfill_reset")
    Fixtures.load!(ScratchRepo, source)
    rows("UPDATE points SET accuracy=20000 WHERE id=170201")
    args = args(source, true)
    parent = self()

    opts = [
      before_month: fn first, last -> send(parent, {:month, first, last}) end,
      after_month: fn _ -> exit(:synthetic_interruption) end
    ]

    assert catch_exit(AnomalyBackfill.run(ScratchRepo, args, opts)) == :synthetic_interruption
    assert rows("SELECT anomaly FROM points WHERE id=170201") == [[true]]
    progress = State.cursor(ScratchRepo, key(args)) |> Jason.decode!()

    assert progress == %{
             "completed" => ["reset_flags"],
             "current" => ["filter_months", 1_733_011_200]
           }

    assert rows("SELECT count(*) FROM phoenix.leases") == [[0]]

    stolen = fn _, _ ->
      rows("UPDATE phoenix.leases SET holder='stolen' WHERE name='anomaly_backfill:170101'")
    end

    assert_raise RuntimeError, "anomaly backfill lease lost", fn ->
      AnomalyBackfill.run(ScratchRepo, args, before_month: stolen)
    end

    assert State.cursor(ScratchRepo, key(args)) |> Jason.decode!() == progress
    rows("DELETE FROM phoenix.leases WHERE name='anomaly_backfill:170101' AND holder='stolen'")

    assert AnomalyBackfill.run(ScratchRepo, args, Keyword.delete(opts, :after_month)) ==
             {:ok, true}

    assert rows("SELECT anomaly FROM points WHERE id=170201") == [[true]]
    assert State.cursor(ScratchRepo, key(args)) == nil

    expected =
      for call <- source["expected"]["calls"],
          call["kind"] == "filter",
          do: {:month, Enum.at(call["args"], 1), Enum.at(call["args"], 2)}

    assert events() == expected
    assert rows("SELECT count(*) FROM phoenix.leases") == [[0]]
  end

  test "invalidates tiles on all-clear reset and preserves non-reset dependents" do
    source = Fixtures.case!("backfill_reset")
    Fixtures.load!(ScratchRepo, source)
    assert AnomalyBackfill.run(ScratchRepo, args(source, true)) == {:ok, true}

    assert rows("SELECT kind,payload FROM phoenix.rails_commands") == [
             ["points.tile_epoch", %{"user_id" => 170_101, "timestamps" => []}]
           ]

    assert rows("SELECT count(*) FROM points WHERE anomaly IS TRUE") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.achievement_checks") == [[0]]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]

    reset!(ScratchRepo)
    Fixtures.load!(ScratchRepo, source)
    rows("UPDATE points SET accuracy=20000, anomaly=false WHERE id=170203")
    assert AnomalyBackfill.run(ScratchRepo, args(source, false)) == {:ok, true}
    assert rows("SELECT anomaly FROM points WHERE id=170201") == [[true]]
    assert rows("SELECT anomaly,track_id FROM points WHERE id=170203") == [[true, nil]]

    assert [
             [
               "points.anomaly_stats",
               %{
                 "user_id" => 170_101,
                 "year" => 2025,
                 "month" => 3,
                 "time_zone" => "Europe/Berlin",
                 "job_queue" => "low_priority"
               }
             ]
           ] =
             rows(
               "SELECT kind,payload FROM phoenix.rails_commands WHERE kind='points.anomaly_stats'"
             )

    assert rows("SELECT count(*) FROM phoenix.achievement_checks") == [[1]]
    assert rows("SELECT count(*) FROM phoenix.cursors") == [[0]]
    rows("UPDATE points SET anomaly=false WHERE id=170203")

    completed =
      args(source, false)
      |> Map.put("progress", %{"completed" => ["reset_flags", "filter_months"]})

    assert AnomalyBackfill.run(ScratchRepo, completed) == {:ok, true}
    assert rows("SELECT anomaly FROM points WHERE id=170203") == [[false]]
  end

  defp args(source, reset) do
    %{
      "user_id" => 170_101,
      "reset" => reset,
      "notify" => false,
      "rebuild" => "inline",
      "source_job_id" => source["job"]["job_id"],
      "ambient_zone" => "Europe/Berlin",
      "progress" => %{},
      "event_id" => source["job"]["job_id"]
    }
  end

  defp key(args), do: "anomaly_backfill:progress:" <> args["event_id"]

  defp events do
    receive do
      {:month, _, _} = event -> [event | events()]
    after
      0 -> []
    end
  end
end
