defmodule Dawarich.Jobs.A12d2CorpusTest do
  use Dawarich.JobsCase
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Integrations.SyncScheduling
  alias Dawarich.Achievements.{BulkCheck, BulkCheckWorker}
  alias Dawarich.Tracks.BackfillWorker
  @oban __MODULE__.Oban
  @now ~U[2026-10-04 12:00:00Z]
  @slot 1_791_115_200

  @tag :rails_parity
  @tag :a12d2_reverse_handoff
  test "publishes actual reverse rows for the Rails acceptance handoff" do
    start_oban(@oban)
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    for id <- [48_801, 48_802] do
      user(id, %{
        "airtrail_url" => "https://airtrail.example.test",
        "airtrail_api_key" => "synthetic",
        "teslamate_url" => "https://teslamate.example.test"
      })

      source(id + 20, id)
    end

    for kind <- [:airtrail, :teslamate, :trek] do
      Ownership.put!(ScratchRepo, SyncScheduling.key(kind), :oban)
      assert SyncScheduling.run(ScratchRepo, @oban, kind, @slot, now: @now) == :ok
    end

    for {id, cycle} <- [
          {48_801, "00000000-0000-4000-8000-000000048801"},
          {48_802, "00000000-0000-4000-8000-000000048802"}
        ] do
      rows(
        "INSERT INTO phoenix.track_backfill_ranges(user_id,earliest_timestamp,latest_timestamp,cycle_id,time_zone,due_at,expires_at) VALUES($1,$2,$3,$4,'Europe/Berlin',$5,$6)",
        [
          id,
          DateTime.to_unix(@now) - 86_400,
          DateTime.to_unix(@now) - 43_200,
          Ecto.UUID.dump!(cycle),
          @now,
          DateTime.add(@now, 21_600)
        ]
      )

      assert BackfillWorker.run(ScratchRepo, @oban, %{"user_id" => id, "cycle_id" => cycle},
               now: @now
             ) == :ok

      assert Processed.done?(ScratchRepo, cycle)
    end

    reverse = rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id")
    assert length(reverse) == 8

    for [kind, payload] <- reverse do
      assert payload["user_id"] in [48_801, 48_802]

      if kind != "tracks_generate_range",
        do: assert(Ecto.UUID.cast(payload["event_id"]) != :error)
    end

    rows("UPDATE users SET settings='{}' WHERE id=ANY($1)", [[48_801, 48_802]])
    rows("UPDATE trip_sources SET status=1 WHERE id=ANY($1)", [[48_821, 48_822]])

    for {kind, first} <- [airtrail: 51_001, teslamate: 53_001, trek: 55_001] do
      for id <- first..(first + 1000) do
        settings =
          case kind do
            :airtrail ->
              %{
                "airtrail_url" => "https://cron-airtrail.example.test",
                "airtrail_api_key" => "synthetic"
              }

            :teslamate ->
              %{"teslamate_url" => "https://cron-teslamate.example.test"}

            :trek ->
              %{}
          end

        user(id, settings)
        if kind == :trek, do: source(id, id)
      end

      key = SyncScheduling.key(kind)
      Ownership.put!(ScratchRepo, key, :oban)
      hook = release_hook(key, first + 999)

      assert SyncScheduling.run(ScratchRepo, @oban, kind, @slot, now: @now, hook: hook) ==
               {:cancel, :not_owner}

      assert_receive {:releasing, task}
      assert Task.await(task) == :ok

      for id <- first..(first + 999) do
        assert Processed.done?(ScratchRepo, SyncScheduling.receipt_id(kind, @slot, id))
      end

      refute Processed.done?(ScratchRepo, SyncScheduling.receipt_id(kind, @slot, first + 1000))
    end

    for id <- 57_001..57_201 do
      user(id, %{})

      rows(
        "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) VALUES($1,1780300000,ST_SetSRID(ST_MakePoint(13,52),4326),now(),now())",
        [id]
      )
    end

    Ownership.put!(ScratchRepo, BulkCheckWorker.key(), :oban)

    assert BulkCheckWorker.run_cron(ScratchRepo, @oban, @slot,
             now: @now,
             hook: achievement_release_hook()
           ) == {:cancel, :not_owner}

    assert_receive {:releasing, task}
    assert Task.await(task) == :ok

    published =
      rows(
        "SELECT (payload->>'user_id')::bigint FROM phoenix.rails_commands WHERE kind='achievements.bulk_check_leaf'"
      )
      |> List.flatten()

    assert length(published) == 200

    for id <- published,
        do:
          assert(Processed.done?(ScratchRepo, BulkCheck.receipt_id(BulkCheck.cron_id(@slot), id)))

    for id <- Enum.to_list(57_001..57_201) -- published,
        do:
          refute(Processed.done?(ScratchRepo, BulkCheck.receipt_id(BulkCheck.cron_id(@slot), id)))

    assert rows(
             "SELECT count(*) FROM phoenix.rails_commands WHERE (payload->>'user_id')::bigint BETWEEN 51001 AND 57201"
           ) == [[3200]]

    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
  end

  defp achievement_release_hook do
    Process.put(:achievement_handoff_count, 0)
    release = release_hook(BulkCheckWorker.key(), nil)

    fn _ ->
      count = Process.get(:achievement_handoff_count) + 1
      Process.put(:achievement_handoff_count, count)
      if count == 200, do: release.(nil)
    end
  end

  defp release_hook(key, last) do
    parent = self()

    fn id ->
      if id == last do
        task = Task.async(fn -> Ownership.put!(ScratchRepo, key, :sidekiq) end)

        assert Dawarich.LockRace.wait_until(fn ->
                 Dawarich.LockRace.blocked("INSERT INTO phoenix.job_owners%") > 0
               end)

        send(parent, {:releasing, task})
      end
    end
  end

  defp user(id, settings),
    do:
      rows(
        "INSERT INTO users(id,email,status,plan,settings,created_at,updated_at) VALUES($1,$2,1,1,$3,now(),now())",
        [id, "a12d2-handoff-#{id}@example.test", settings]
      )

  defp source(id, user),
    do:
      rows(
        "INSERT INTO trip_sources(id,user_id,status,provider,base_url,api_key,created_at,updated_at) VALUES($1,$2,0,'trek',$3,'synthetic',now(),now())",
        [id, user, "https://a12d2-handoff-#{id}.example.test"]
      )
end
