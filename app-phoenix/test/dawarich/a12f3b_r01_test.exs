defmodule Dawarich.A12f3bR01Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.AnomalyCase
  alias Dawarich.Ingest.Intake
  alias Dawarich.Cable.Bus
  alias Dawarich.Jobs.Ownership

  @at DateTime.to_unix(~U[2026-01-01 00:00:00Z])

  setup do
    rails = System.get_env("DAWARICH_RAILS")
    cable = Application.get_env(:dawarich, :cable)
    System.put_env("DAWARICH_RAILS", "off")
    Application.put_env(:dawarich, :cable, transport: :pg, repo: ScratchRepo, polling: false)

    on_exit(fn ->
      if rails,
        do: System.put_env("DAWARICH_RAILS", rails),
        else: System.delete_env("DAWARICH_RAILS")

      Application.put_env(:dawarich, :cable, cable)
    end)

    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    :ok
  end

  @tag a12f3b_case: "R01k01"
  test "points.tile_epoch native producer reaches its source terminal effect" do
    user = user!()
    before = Dawarich.Tiles.Http.epoch("points", user, {@at - 1, @at})

    {:ok, _} =
      ScratchRepo.transaction(fn ->
        Dawarich.RailsEffects.tile_epoch(ScratchRepo, user, [@at - 1, @at])
      end)

    assert [[args]] = jobs("Dawarich.Points.TileEpochWorker")
    assert :ok = Dawarich.Points.TileEpochWorker.run(ScratchRepo, args)
    refute Dawarich.Tiles.Http.epoch("points", user, {@at - 1, @at}) == before
    assert :ok = Dawarich.Points.TileEpochWorker.run(ScratchRepo, args)
    assert reverse("points.tile_epoch") == []

    {:error, :rollback} =
      ScratchRepo.transaction(fn ->
        Dawarich.RailsEffects.tile_epoch(ScratchRepo, user, [])
        ScratchRepo.rollback(:rollback)
      end)

    assert length(jobs("Dawarich.Points.TileEpochWorker")) == 1

    coexist("points.tile_epoch", fn ->
      Dawarich.RailsEffects.tile_epoch(ScratchRepo, user, [@at])
    end)
  end

  @tag a12f3b_case: "R01k02"
  test "points.live_broadcast native producer reaches its source terminal effect" do
    user =
      user!(%{
        "live_map_enabled" => true,
        "family" => %{"location_sharing" => %{"enabled" => true}}
      })

    [[family]] =
      rows(
        "INSERT INTO families(name,creator_id,created_at,updated_at) VALUES('Synthetic family',$1,now(),now()) RETURNING id",
        [user]
      )

    rows(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,0,now(),now())",
      [family, user]
    )

    share = Ecto.UUID.generate()

    rows(
      "INSERT INTO shared_links(id,user_id,name,resource_type,settings,created_at,updated_at) VALUES($1,$2,'Synthetic live',3,'{}',now(),now())",
      [Ecto.UUID.dump!(share), user]
    )

    [[place]] =
      rows(
        "INSERT INTO places(user_id,name,latitude,longitude,created_at,updated_at) VALUES($1,'Synthetic private',52.5,13.4,now(),now()) RETURNING id",
        [user]
      )

    [[tag]] =
      rows(
        "INSERT INTO tags(user_id,name,privacy_radius_meters,created_at,updated_at) VALUES($1,'Synthetic privacy',100,now(),now()) RETURNING id",
        [user]
      )

    rows(
      "INSERT INTO taggings(tag_id,taggable_type,taggable_id,created_at,updated_at) VALUES($1,'Place',$2,now(),now())",
      [tag, place]
    )

    [spec] = Bus.child_specs()
    start_supervised!(spec)
    stream = Dawarich.RailsMessages.broadcasting(["points", {:user, user}])
    {:ok, ref} = Bus.subscribe(stream)
    assert_receive {:cable_pg, _, _, :subscribed, ^stream, ^ref}
    family_stream = Dawarich.RailsMessages.broadcasting(["family_locations", {:family, family}])
    share_stream = Dawarich.RailsMessages.broadcasting(["shared_location", {:shared_link, share}])

    for topic <- [family_stream, share_stream] do
      {:ok, ref} = Bus.subscribe(topic)
      assert_receive {:cable_pg, _, _, :subscribed, ^topic, ^ref}
    end

    [%{id: id}] = ingest(user)
    assert [[args]] = jobs("Dawarich.Points.LiveBroadcastWorker")
    assert :ok = Dawarich.Points.LiveBroadcastWorker.run(ScratchRepo, args)
    send(Bus, :poll)
    :sys.get_state(Bus)
    assert_receive {:cable_pg, _, _, ^stream, _, bytes}

    assert Jason.decode!(bytes) == [
             52.5,
             13.4,
             "80",
             "12.5",
             to_string(@at),
             "3",
             to_string(id),
             ""
           ]

    assert_receive {:cable_pg, _, _, ^family_stream, _, family_bytes}

    assert %{"user_id" => ^user, "latitude" => 52.5, "longitude" => 13.4} =
             Jason.decode!(family_bytes)

    assert_receive {:cable_pg, _, _, ^share_stream, _, share_bytes}
    assert Jason.decode!(share_bytes) == %{"masked" => true}
    assert :ok = Dawarich.Points.LiveBroadcastWorker.run(ScratchRepo, args)
    assert rows("SELECT count(*) FROM phoenix.cable_events WHERE channel=$1", [stream]) == [[1]]
    assert reverse("points.live_broadcast") == []
    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [user])

    assert :ok =
             Dawarich.Points.LiveBroadcastWorker.run(
               ScratchRepo,
               Map.put(args, "broadcast_id", Ecto.UUID.generate())
             )

    assert rows("SELECT count(*) FROM phoenix.cable_events") == [[3]]
    rows("UPDATE users SET deleted_at=NULL WHERE id=$1", [user])
    coexist("points.live_broadcast", fn -> ingest(user) end)
  end

  @tag a12f3b_case: "R01k03"
  test "tracks.realtime native producer reaches its source terminal effect" do
    user = user!()
    now = DateTime.utc_now()
    ingest(user, now: now)
    ingest(user, now: DateTime.add(now, 10))
    assert [[%{"user_id" => ^user}]] = jobs("Dawarich.Points.RealtimeTracksWorker")

    assert [[due]] =
             rows(
               "SELECT scheduled_at FROM oban.oban_jobs WHERE worker='Dawarich.Points.RealtimeTracksWorker'"
             )

    assert NaiveDateTime.diff(due, DateTime.to_naive(now)) == 45

    assert rows("SELECT key FROM phoenix.once_claims WHERE key=$1", [
             "track_realtime:user:#{user}"
           ]) == [["track_realtime:user:#{user}"]]

    assert reverse("tracks.realtime") == []
    coexist("tracks.generate_realtime", fn -> ingest(user) end, "tracks.realtime")
  end

  @tag a12f3b_case: "R01k04"
  test "visits.realtime native producer reaches its source terminal effect" do
    user = user!(%{"visits_suggestions_enabled" => "true", "timezone" => "Pacific/Chatham"})

    rows(
      "INSERT INTO instance_settings(key,value,created_at,updated_at) VALUES('photon_api_host','\"photon.example.test\"',now(),now())"
    )

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    ingest(user, now: now)
    ingest(user, now: DateTime.add(now, 10))

    assert [[args, due]] =
             rows(
               "SELECT payload,scheduled_at FROM public.job_outbox WHERE command_type='visits.suggest'"
             )

    assert args == %{
             "user_id" => user,
             "time_zone" => "Pacific/Chatham",
             "start_at" => DateTime.to_unix(now) - 21_600,
             "end_at" => DateTime.to_unix(now),
             "stepping" => "calendar",
             "plan_restricted" => false
           }

    assert rows(
             "SELECT command_version,aggregate_id,metadata FROM public.job_outbox WHERE command_type='visits.suggest'"
           ) == [[1, user, %{"producer" => "Visits::RealtimeDebouncer"}]]

    assert DateTime.diff(due, now) == 300
    assert reverse("visits.realtime") == []

    rows(
      "UPDATE users SET settings=jsonb_set(settings,'{visits_suggestions_enabled}','\"false\"') WHERE id=$1",
      [user]
    )

    rows("DELETE FROM phoenix.once_claims")
    ingest(user)

    assert rows("SELECT count(*) FROM public.job_outbox WHERE command_type='visits.suggest'") ==
             [[1]]

    coexist("visits.suggest", fn -> ingest(user) end, "visits.realtime")
  end

  test "visit arrivals expose only the shared Visits scheduler" do
    assert Code.ensure_loaded?(Dawarich.Visits.RealtimeDebouncer)
    assert Code.ensure_loaded?(Dawarich.Points.Realtime)
    refute function_exported?(Dawarich.Points.Realtime, :visits, 3)
    refute Code.ensure_loaded?(Dawarich.Points.RealtimeVisitsWorker)
  end

  @tag a12f3b_case: "R01k05"
  test "native point effect ownership handoff supplies executable versioned workers" do
    payloads = %{
      "command:points.tile_epoch" => %{"user_id" => 1, "timestamps" => [@at, nil]},
      "command:points.live_broadcast" => %{
        "user_id" => 1,
        "broadcast_id" => Ecto.UUID.generate(),
        "upserted" => [%{"id" => 1, "timestamp" => @at, "latitude" => 52.5, "longitude" => 13.4}],
        "payloads" => [
          %{"timestamp" => @at, "battery" => 80, "altitude" => 12.5, "velocity" => "3"}
        ]
      },
      "command:points.anomaly_filter" => %{
        "user_id" => 1,
        "start_at" => @at,
        "end_at" => @at,
        "time_zone" => "UTC"
      }
    }

    entries = Dawarich.Points.JobEntries.entries()
    assert Enum.sort(Enum.map(entries, & &1.key)) == Enum.sort(Map.keys(payloads))

    for entry <- entries do
      payload = payloads[entry.key]
      assert {:ok, ^payload} = entry.worker.args_from_command(1, payload)
      assert {:error, "unsupported_version"} = entry.worker.args_from_command(2, payload)

      assert {:error, "invalid_payload"} =
               entry.worker.args_from_command(1, Map.put(payload, "unexpected", true))
    end
  end

  defp ingest(user, opts \\ []) do
    Intake.prepare(
      [%{lonlat: "POINT(13.4 52.5)", timestamp: @at, battery: 80, altitude: 12.5, velocity: "3"}],
      user
    )
    |> Intake.write(user, Keyword.put(opts, :repo, ScratchRepo))
  end

  defp jobs(worker),
    do: rows("SELECT args FROM oban.oban_jobs WHERE worker=$1 ORDER BY id", [worker])

  defp reverse(kind), do: rows("SELECT payload FROM phoenix.rails_commands WHERE kind=$1", [kind])

  defp coexist(key, fun, kind \\ nil) do
    System.delete_env("DAWARICH_RAILS")
    Ownership.put!(ScratchRepo, "command:" <> key, :oban)
    fun.()
    assert reverse(kind || key) == []
    Ownership.put!(ScratchRepo, "command:" <> key, :sidekiq, pinned: true)
    fun.()
    assert length(reverse(kind || key)) == 1
  end
end
