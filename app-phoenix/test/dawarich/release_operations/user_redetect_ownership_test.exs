defmodule Dawarich.ReleaseOperations.UserRedetectOwnershipTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Jobs.{Ownership, Registry}
  alias Dawarich.ReleaseOperations.VisitsFleetRedetect
  alias Dawarich.Visits.UserRedetectWorker
  alias Dawarich.Wave6Fixtures, as: F

  setup do
    previous = System.get_env("DAWARICH_RAILS")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    start_oban(__MODULE__)
    for entry <- Registry.entries(), do: Ownership.put!(ScratchRepo, entry.key, :oban)
    :ok
  end

  @tag a12f3b_case: "R19k06"
  test "fleet user redetection completes natively with every registered owner and retains Rails hand-back" do
    assert {:oban, ["command:visits.user_redetect"], :a12d2} ==
             Dawarich.RailsJobOwners.owners()["Visits::UserRedetectJob"]

    for mode <- ["on", "off"] do
      System.put_env("DAWARICH_RAILS", mode)
      user = F.user!(%{"points_count" => 1})
      F.point!(user, %{"timestamp" => 1_767_225_600})
      parent = Ecto.UUID.generate()

      job = %Oban.Job{
        args: %{
          "version" => 1,
          "event_id" => parent,
          "cursor" => %{"after_id" => 0, "started_at" => nil, "offset" => 0}
        },
        attempt: 1,
        max_attempts: 10
      }

      assert :ok ==
               Dawarich.ReleaseOperations.run(ScratchRepo, __MODULE__, VisitsFleetRedetect, job)

      assert [] == rows("SELECT kind FROM phoenix.rails_commands")
      assert {:ok, UserRedetectWorker} == Registry.command("visits.user_redetect")

      assert [[payload, metadata, due]] =
               rows(
                 "SELECT payload,metadata,scheduled_at FROM job_outbox WHERE command_type='visits.user_redetect' AND aggregate_id=$1",
                 [user]
               )

      assert payload["user_id"] == user
      assert payload["lock_attempts"] == 0
      assert metadata["parent_event_id"] == parent

      assert [["completed"]] ==
               rows("SELECT status FROM phoenix.release_operations WHERE id=$1", [
                 Ecto.UUID.dump!(parent)
               ])

      assert %{dispatched: 1} == Dawarich.Jobs.Dispatch.run(repo: ScratchRepo, oban: __MODULE__)

      assert %{success: 1, failure: 0} =
               Oban.drain_queue(__MODULE__, queue: :visit_suggesting, with_scheduled: true)

      assert [[true]] ==
               rows("SELECT visits_redetected_at IS NOT NULL FROM users WHERE id=$1", [user])

      assert [[event]] =
               rows(
                 "SELECT args->>'event_id' FROM oban.oban_jobs WHERE worker=$1 AND (args->>'user_id')::bigint=$2",
                 ["Dawarich.Visits.UserRedetectWorker", user]
               )

      assert Dawarich.Jobs.Processed.done?(ScratchRepo, event)
      assert :ok == UserRedetectWorker.run(ScratchRepo, Map.put(payload, "event_id", event))
      assert [] == rows("SELECT kind FROM phoenix.rails_commands")
      rows("UPDATE users SET points_count=0 WHERE id=$1", [user])
      rows("DELETE FROM job_outbox")
      rows("DELETE FROM oban.oban_jobs")

      Ownership.put!(ScratchRepo, "command:visits.user_redetect", :sidekiq, pinned: true)
      at = due |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

      assert {:ok, :ok} ==
               ScratchRepo.transaction(fn ->
                 UserRedetectWorker.enqueue(ScratchRepo, user, at, parent)
               end)

      if mode == "on" do
        assert [["release_user_redetect", ~s({"run_at": #{at}, "user_id": #{user}})]] ==
                 rows("SELECT kind,payload::text FROM phoenix.rails_commands")

        assert [] == rows("SELECT command_type FROM job_outbox")
      else
        assert [] == rows("SELECT kind FROM phoenix.rails_commands")
        assert [["visits.user_redetect"]] == rows("SELECT command_type FROM job_outbox")
      end

      rows("DELETE FROM job_outbox")
      rows("DELETE FROM phoenix.rails_commands")
      Ownership.put!(ScratchRepo, "command:visits.user_redetect", :oban)
    end
  end
end
