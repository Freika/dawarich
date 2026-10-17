defmodule Dawarich.Families.JobWorkersTest do
  use Dawarich.JobsCase

  alias Dawarich.Families.{AutoCreateWorker, MemberSyncWorker}
  alias Dawarich.Jobs.Processed

  @now ~U[2026-10-04 12:00:00Z]

  setup do
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "false")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    :ok
  end

  test "family workers decode exact owner ids and replay committed effects once" do
    [[user]] =
      rows(
        "INSERT INTO users (email, plan, settings, active_until, created_at, updated_at) VALUES ('family-workers@example.test', 2, $1, $2, now(), now()) RETURNING id",
        [%{"locale" => "de"}, ~N[2026-10-05 12:00:00.000000]]
      )

    auto = %{"user_id" => user, "time_zone" => "Berlin"}
    assert AutoCreateWorker.args_from_command(1, auto) == {:ok, auto}

    assert AutoCreateWorker.args_from_command(1, Map.put(auto, "user_id", to_string(user))) ==
             {:ok, auto}

    for payload <- [
          Map.put(auto, "extra", 1),
          Map.put(auto, "user_id", "invalid"),
          Map.delete(auto, "time_zone")
        ],
        do: assert(AutoCreateWorker.args_from_command(1, payload) == {:error, "invalid_payload"})

    assert AutoCreateWorker.args_from_command(2, auto) == {:error, "unsupported_version"}
    event = Ecto.UUID.generate()
    args = Map.put(auto, "event_id", event)
    assert AutoCreateWorker.run(ScratchRepo, args, now: @now) == :ok
    assert AutoCreateWorker.run(ScratchRepo, args, now: @now) == :ok
    assert Processed.done?(ScratchRepo, event)
    assert rows("SELECT count(*) FROM families") == [[1]]
    assert rows("SELECT count(*) FROM notifications") == [[1]]
    [[family]] = rows("SELECT id FROM families WHERE creator_id = $1", [user])

    [[member]] =
      rows(
        "INSERT INTO users (email, plan, status, created_at, updated_at) VALUES ('family-worker-member@example.test', 0, 0, now(), now()) RETURNING id"
      )

    rows(
      "INSERT INTO family_memberships (family_id, user_id, created_at, updated_at) VALUES ($1, $2, now(), now())",
      [family, member]
    )

    sync = %{"family_id" => family, "locale" => "de", "time_zone" => "UTC"}
    assert MemberSyncWorker.args_from_command(1, sync) == {:ok, sync}

    assert MemberSyncWorker.args_from_command(1, Map.put(sync, "family_id", to_string(family))) ==
             {:ok, sync}

    for payload <- [
          Map.put(sync, "extra", 1),
          Map.put(sync, "family_id", "invalid"),
          Map.delete(sync, "locale")
        ],
        do: assert(MemberSyncWorker.args_from_command(1, payload) == {:error, "invalid_payload"})

    assert MemberSyncWorker.args_from_command(2, sync) == {:error, "unsupported_version"}
    sync_event = Ecto.UUID.generate()
    args = Map.put(sync, "event_id", sync_event)

    assert_raise Postgrex.Error, fn ->
      MemberSyncWorker.run(ScratchRepo, args,
        now: @now,
        hook: fn _ -> ScratchRepo.query!("SELECT 1 / 0", [], log: false) end
      )
    end

    refute Processed.done?(ScratchRepo, sync_event)
    assert rows("SELECT plan FROM users WHERE id = $1", [member]) == [[0]]
    assert MemberSyncWorker.run(ScratchRepo, args, now: @now) == :ok
    assert rows("SELECT plan, status FROM users WHERE id = $1", [member]) == [[1, 1]]

    rows("UPDATE users SET active_until = $2 WHERE id = $1", [
      user,
      ~N[2026-10-03 12:00:00.000000]
    ])

    assert MemberSyncWorker.run(ScratchRepo, args, now: @now) == :ok
    assert rows("SELECT plan FROM users WHERE id = $1", [member]) == [[1]]

    for worker <- [AutoCreateWorker, MemberSyncWorker] do
      assert worker.__opts__()[:max_attempts] == 26
      assert worker.__opts__()[:queue] == :maintenance
      assert worker.backoff(%Oban.Job{attempt: 10}) in 6576..6675
    end
  end
end
