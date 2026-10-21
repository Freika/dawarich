defmodule Dawarich.AirTrail.SyncSchedulingWorkerTest do
  use Dawarich.JobsCase

  alias Dawarich.AirTrail.{ImportFlightsWorker, SyncSchedulingWorker}
  alias Dawarich.Jobs.{Ownership, Processed}

  @slot 1_759_050_000
  @cron "cron:airtrail_flight_import_job"
  @leaf "command:imports.airtrail_flights"
  @oban __MODULE__.Oban

  setup do
    start_oban(@oban)
    :ok
  end

  defp user!(settings, status \\ 1, deleted \\ nil) do
    [[id]] =
      rows(
        "INSERT INTO users (email, settings, status, deleted_at, created_at, updated_at) " <>
          "VALUES ($1, $2, $3, $4, now(), now()) RETURNING id",
        [
          "scheduler-#{System.unique_integer([:positive])}@example.test",
          settings,
          status,
          deleted
        ]
      )

    id
  end

  defp configured, do: %{"airtrail_url" => "https://airtrail.example", "airtrail_api_key" => "k"}

  defp jobs,
    do:
      rows("SELECT args FROM oban.oban_jobs WHERE worker = $1 ORDER BY id", [
        inspect(ImportFlightsWorker)
      ])
      |> List.flatten()

  defp commands, do: rows("SELECT kind, payload FROM phoenix.rails_commands ORDER BY id")
  defp claims, do: rows("SELECT event_id FROM phoenix.processed_commands ORDER BY event_id")
  defp run(opts \\ []), do: SyncSchedulingWorker.run(ScratchRepo, @oban, @slot, opts)

  test "AirTrail schedules exactly configured users through each leaf owner" do
    Ownership.put!(ScratchRepo, @cron, :oban)
    Ownership.put!(ScratchRepo, @leaf, :oban)
    inactive = user!(configured(), 0)
    whitespace = user!(%{"airtrail_url" => " ", "airtrail_api_key" => " "}, 3)

    for settings <- [
          %{},
          %{"airtrail_url" => "", "airtrail_api_key" => "k"},
          %{"airtrail_url" => "https://a", "airtrail_api_key" => nil},
          %{"airtrail_url" => nil, "airtrail_api_key" => "k"},
          %{"airtrail_url" => "https://a", "airtrail_api_key" => ""}
        ],
        do: user!(settings)

    user!(configured(), 1, DateTime.utc_now() |> DateTime.to_naive())

    additional =
      rows(
        "INSERT INTO users (email, settings, created_at, updated_at) " <>
          "SELECT 'airtrail-batch-' || g || '@example.test', $1, now(), now() FROM generate_series(1,1001) g RETURNING id",
        [configured()]
      )
      |> List.flatten()

    ids = [inactive, whitespace] ++ additional

    expected =
      Enum.map(ids, &%{"user_id" => &1, "event_id" => SyncSchedulingWorker.event_id(@slot, &1)})

    assert SyncSchedulingWorker.slot(%Oban.Job{inserted_at: ~U[2025-09-28 09:00:07Z]}) == @slot
    assert run() == :ok
    assert jobs() == expected
    assert length(claims()) == length(ids)
    assert commands() == []
    refute Processed.done?(ScratchRepo, SyncSchedulingWorker.event_id(@slot, inactive))
    assert run() == :ok
    assert jobs() == expected

    rows("DELETE FROM oban.oban_jobs")
    Ownership.put!(ScratchRepo, @leaf, :sidekiq)
    assert SyncSchedulingWorker.run(ScratchRepo, @oban, @slot + 60) == :ok

    assert commands() ==
             Enum.map(ids, fn id ->
               [
                 "integrations.airtrail_flights",
                 %{"user_id" => id, "event_id" => SyncSchedulingWorker.event_id(@slot + 60, id)}
               ]
             end)

    assert jobs() == []
  end

  test "released AirTrail cron cancels and failed batch publishes no partial receipt" do
    first = user!(configured())
    failing = user!(configured())
    assert run() == {:cancel, :not_owner}
    assert claims() == []
    assert commands() == []
    Ownership.put!(ScratchRepo, @cron, :oban)

    hook = fn
      ^failing -> ScratchRepo.query!("SELECT 1 / 0", [], log: false)
      _ -> :ok
    end

    assert_raise Postgrex.Error, fn -> run(hook: hook) end
    refute Processed.done?(ScratchRepo, SyncSchedulingWorker.receipt_id(@slot, first))
    assert claims() == []
    assert commands() == []
    assert jobs() == []
    assert run() == :ok
    assert length(commands()) == 2
    assert run() == :ok
    assert length(commands()) == 2
    Ownership.put!(ScratchRepo, @cron, :sidekiq)
    assert SyncSchedulingWorker.run(ScratchRepo, @oban, @slot + 60) == {:cancel, :not_owner}
    assert length(commands()) == 2
  end
end
