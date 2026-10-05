defmodule Dawarich.Jobs.ReleaseAdaptersTest do
  use Dawarich.JobsCase
  alias Dawarich.Jobs.{Dispatch, Ownership, Registry}
  alias Dawarich.ReleaseOperations.{Achievements, ImportBackfill}

  @oban __MODULE__.Oban

  setup do
    start_oban(@oban)
    :ok
  end

  test "two release adapter keys default off and quarantine invalid versions before effects" do
    entries = Registry.entries()

    for {type, worker, payload} <- [
          {"release.achievements_backfill", Achievements, %{}},
          {"release.import_backfill", ImportBackfill,
           %{"import_id" => 54001, "ambient_zone" => "Europe/Berlin"}}
        ] do
      assert Registry.command(type) == {:ok, worker}
      entry = Enum.find(entries, &(&1.key == "command:" <> type))
      assert entry.claimable == false
      refute entry in Registry.claimable()
      assert entry.kind == :command
      assert Ownership.lock(ScratchRepo, entry.key) == :sidekiq
      job = worker.new(%{})
      assert Ecto.Changeset.get_field(job, :max_attempts) == 26
      assert Ecto.Changeset.get_field(job, :queue) == "maintenance"
      assert Ecto.Changeset.get_field(job, :priority) == 3
      assert {:ok, args} = worker.args_from_command(1, payload)
      assert args["version"] == 1
      assert worker.args_from_command(2, payload) == {:error, "unsupported_version"}

      assert worker.args_from_command(1, Map.put(payload, "extra", 1)) ==
               {:error, "invalid_payload"}

      assert worker.perform(%Oban.Job{args: %{"version" => 2}}) == {:cancel, :unsupported_version}

      bad = outbox!(command_type: type, command_version: 2, payload: payload)
      extra = outbox!(command_type: type, payload: Map.put(payload, "extra", 1))
      assert Dispatch.run(repo: ScratchRepo, oban: @oban) == %{quarantined: 2}

      assert rows("SELECT state,error_code FROM job_outbox WHERE event_id=$1", [
               Ecto.UUID.dump!(bad)
             ]) == [["quarantined", "unsupported_version"]]

      assert rows("SELECT state,error_code FROM job_outbox WHERE event_id=$1", [
               Ecto.UUID.dump!(extra)
             ]) == [["quarantined", "invalid_payload"]]

      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    end

    for payload <- [
          %{},
          %{"import_id" => 1},
          %{"ambient_zone" => "UTC"},
          %{"import_id" => 0, "ambient_zone" => "UTC"},
          %{"import_id" => -1, "ambient_zone" => "UTC"},
          %{"import_id" => "1", "ambient_zone" => "UTC"},
          %{"import_id" => 1, "ambient_zone" => nil},
          %{"import_id" => 1, "ambient_zone" => "../etc/passwd"},
          %{"import_id" => 1, "ambient_zone" => "Not/AZone"}
        ] do
      assert ImportBackfill.args_from_command(1, payload) == {:error, "invalid_payload"}
    end

    assert Achievements.args_from_command(1, %{"import_id" => 1}) == {:error, "invalid_payload"}
    sentinel = "command:achievements.check"
    Ownership.put!(ScratchRepo, sentinel, :oban, pinned: true)

    for key <- ~w(command:release.achievements_backfill command:release.import_backfill) do
      Ownership.put!(ScratchRepo, key, :sidekiq, pinned: true)
      Ownership.put!(ScratchRepo, key, :sidekiq, pinned: false)
    end

    assert rows("SELECT owner,pinned FROM phoenix.job_owners WHERE key=$1", [sentinel]) == [
             ["oban", true]
           ]

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.processed_commands") == [[0]]
  end
end
