defmodule Dawarich.UserData.ExportEventsTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db
  alias Dawarich.UserData.ExportState
  alias Dawarich.Exports.EventsWorker

  test "account backup capture completion and failure publish durable owner invalidations" do
    user =
      Dawarich.Test.RailsUser.insert!(
        %{id: 11083, email: "backup-events@example.invalid"},
        ScratchRepo
      )

    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:users.export_data", :oban)

    assert :ok = Dawarich.Exports.Events.subscribe(user.id)

    for stage <- [:completed, :failed] do
      args = %{"user_id" => user.id, "event_id" => Ecto.UUID.generate(), "time_zone" => "UTC"}
      holder = Ecto.UUID.generate()

      assert Dawarich.State.Lease.acquire(
               ScratchRepo,
               ExportState.lease_name(args),
               holder,
               60_000
             )

      assert {:ok, state} =
               ExportState.capture(ScratchRepo, args, holder, NaiveDateTime.utc_now())

      assert [intent] = events()
      assert :ok = EventsWorker.run(ScratchRepo, intent)
      assert_receive {:domain_changed, owner, :exports}
      assert owner == user.id
      if stage == :completed, do: ExportState.status!(state, 2), else: ExportState.fail!(state)
      assert [^intent, outcome] = events()
      assert :ok = EventsWorker.run(ScratchRepo, outcome)
      assert_receive {:domain_changed, ^owner, :exports}
      assert Enum.sort(Map.keys(outcome)) == ["event_id", "user_id"]
      assert :ok = EventsWorker.run(ScratchRepo, outcome)
      refute_receive {:domain_changed, _, :exports}
      rows("DELETE FROM oban.oban_jobs WHERE worker='Dawarich.Exports.EventsWorker'")
      assert Dawarich.State.Lease.release(ScratchRepo, ExportState.lease_name(args), holder)
    end
  end

  test "restored exports persist their owner invalidation with the row and replay once" do
    user =
      Dawarich.Test.RailsUser.insert!(
        %{id: 11084, email: "restore-events@example.invalid"},
        ScratchRepo
      )

    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:users.export_data", :oban)

    row = %{
      "name" => "restored.zip",
      "file_format" => "archive",
      "file_type" => "user_data",
      "status" => "completed"
    }

    context = %{repo: ScratchRepo, now: NaiveDateTime.utc_now(), locale: "en"}

    assert {:error, :abort} =
             ScratchRepo.transaction(fn ->
               assert [1, 0] =
                        Dawarich.UserData.Restore.Exports.call(
                          ScratchRepo,
                          user.id,
                          [row],
                          "",
                          context
                        )

               assert [_] = events()
               ScratchRepo.rollback(:abort)
             end)

    assert events() == []

    assert [1, 0] =
             Dawarich.UserData.Restore.Exports.call(ScratchRepo, user.id, [row], "", context)

    assert [intent] = events()

    assert [0, 0] =
             Dawarich.UserData.Restore.Exports.call(ScratchRepo, user.id, [row], "", context)

    assert [^intent] = events()
  end

  defp events,
    do:
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Exports.EventsWorker' ORDER BY id"
      )
      |> Enum.map(&hd/1)
end
