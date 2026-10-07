defmodule Dawarich.A12f3bH03Test do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.{Drain, Ownership, Registry}

  setup do
    saved = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if saved,
        do: System.put_env("DAWARICH_RAILS", saved),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    :ok
  end

  @tag a12f3b_case: "H03a"
  test "native producer closure status reflects actual effects and unresolved debt" do
    for entry <- Registry.entries(),
        do: Ownership.put!(ScratchRepo, entry.key, :oban)

    rows(
      "INSERT INTO phoenix.runtime_nodes(node, started_at, beat_at) VALUES ('observer',now(),now())"
    )

    status = Drain.status(ScratchRepo)
    assert status.scope == "native_sql"
    assert status.source.status == "NOT_OBSERVED"
    assert status.source.certainty == "UNKNOWN"
    assert status.g49 == "BLOCKED"
    assert status.counts.reverse_pending == 0
    assert status.forward == "BLOCKED"
    assert "residual_producers" in status.forward_reasons
    assert %{kind: "reverse_geocode_place", status: "BLOCKED"} in status.producer_kinds
    assert length(status.producer_kinds) == length(Dawarich.RailsCommands.closure_kinds())

    assert Dawarich.RailsEffects.reverse_place(ScratchRepo, 1, 9) == :ok
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

    assert rows("SELECT worker,args FROM oban.oban_jobs") ==
             [["Dawarich.Geocoding.ReversePlaceWorker", %{"place_id" => 9}]]

    System.put_env("DAWARICH_RAILS", "on")
    Ownership.put!(ScratchRepo, "command:geocoding.reverse_place", :sidekiq, pinned: true)
    assert Dawarich.RailsEffects.reverse_place(ScratchRepo, 1, 9) == :ok

    assert rows("SELECT kind,payload FROM phoenix.rails_commands") ==
             [["reverse_geocode_place", %{"user_id" => 1, "place_id" => 9}]]

    rows(
      "UPDATE phoenix.rails_commands SET available_at=now()+interval '1 hour',attempts=2,leased_until=now()+interval '1 hour'"
    )

    status = Drain.status(ScratchRepo)
    assert status.counts.reverse_future == 1
    assert status.counts.reverse_leased == 1
    assert status.forward == "BLOCKED"
    assert status.binary_rollback == "BLOCKED"
    assert "reverse_pending" in status.forward_reasons

    assert rows("SELECT payload FROM phoenix.rails_commands") == [
             [%{"user_id" => 1, "place_id" => 9}]
           ]
  end

  @tag a12f3b_case: "H03b"
  test "G49 read failure and DRAIN rollback retain all write safety" do
    unreadable = Drain.status(nil)
    assert unreadable.scope == "native_sql"
    assert unreadable.g49 == "BLOCKED"
    assert unreadable.source.status == "NOT_OBSERVED"
    assert unreadable.certainty == "UNKNOWN"
    assert unreadable.forward == "BLOCKED"
    assert unreadable.binary_rollback == "BLOCKED"
    assert unreadable.shutdown_reasons == ["database_unreadable"]

    for entry <- Registry.entries(),
        do: Ownership.put!(ScratchRepo, entry.key, :sidekiq, pinned: true)

    status = Drain.status(ScratchRepo)
    assert status.binary_rollback == "OBSERVED_EMPTY"
    assert status.g49 == "BLOCKED"
    assert status.source.reasons == ["source_inspection_required"]

    event =
      outbox!(
        command_type: "trips.calculate",
        scheduled_at: DateTime.add(DateTime.utc_now(), 3600)
      )

    before = rows("SELECT event_id,payload,scheduled_at FROM job_outbox")
    assert "pending_outbox" in Drain.status(ScratchRepo).binary_reasons
    assert rows("SELECT event_id,payload,scheduled_at FROM job_outbox") == before
    rows("UPDATE job_outbox SET state='dispatched' WHERE event_id=$1", [Ecto.UUID.dump!(event)])
    assert Drain.status(ScratchRepo).binary_rollback == "OBSERVED_EMPTY"
    Ownership.put!(ScratchRepo, "command:trips.calculate", :sidekiq, pinned: false)
    assert "unpinned_rollback_owners" in Drain.status(ScratchRepo).binary_reasons
  end
end
