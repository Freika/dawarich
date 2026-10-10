defmodule Dawarich.A12f3bE13Test do
  use Dawarich.JobsCase, async: false

  alias Dawarich.{PointExports, ScratchRepo}
  alias Dawarich.Jobs.{Dispatch, Drain, Ownership, Processed, Registry}
  alias Dawarich.Posters.{Command, Generation}
  alias Dawarich.RouteVideos.PurgeWorker

  setup do
    root = Path.join(System.tmp_dir!(), "media-source-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    previous = Application.fetch_env!(:dawarich, :rails_root)
    cable = Application.fetch_env!(:dawarich, :cable)
    env = Map.take(System.get_env(), ~w(DAWARICH_RAILS STORAGE_BACKEND))
    Application.put_env(:dawarich, :rails_root, root)
    Application.put_env(:dawarich, :cable, transport: :pg)
    System.put_env("DAWARICH_RAILS", "off")
    System.delete_env("STORAGE_BACKEND")
    start_oban(__MODULE__)

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_root, previous)
      Application.put_env(:dawarich, :cable, cable)

      for key <- ~w(DAWARICH_RAILS STORAGE_BACKEND) do
        if env[key], do: System.put_env(key, env[key]), else: System.delete_env(key)
      end

      File.rm_rf!(root)
    end)

    %{root: root, source: source_queues()}
  end

  @tag a12f3b_case: "E13a"
  test "E13 native owner accepts every retained argument and continuation shape", c do
    state = poster_fixture!()
    user = %{id: state["actor_id"], settings: %{"timezone" => "America/New_York"}}
    id = state["before"]["id"]
    now = NaiveDateTime.add(DateTime.to_naive(Dawarich.JobsCase.db_now(ScratchRepo)), -1)

    Command.produce(ScratchRepo, :sidekiq, id, user, "fr", now)

    assert %{dispatched: 1} =
             Dispatch.run(
               now: Dawarich.JobsCase.db_now(ScratchRepo),
               repo: ScratchRepo,
               oban: __MODULE__
             )

    [[args]] = rows("SELECT args FROM oban.oban_jobs")
    assert args["locale"] == "fr"
    assert Ecto.UUID.cast(args["event_id"]) == {:ok, args["event_id"]}

    assert :ok =
             Generation.run(id, user.id, args["event_id"], "fr",
               repo: ScratchRepo,
               renderer: fn _, _, locale ->
                 assert locale == "fr"
                 %{png: "synthetic png", pdf: "synthetic pdf"}
               end,
               storage: %{root: Path.join(c.root, "storage"), service: "local"}
             )

    assert rows("SELECT status FROM posters WHERE id=$1", [id]) == [[2]]

    assert rows(
             "SELECT name FROM active_storage_attachments WHERE record_type='Poster' ORDER BY name"
           ) == [["image"], ["print_pdf"]]

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Posters.ProgressWorker'"
           ) == [[3]]

    assert %{success: 4, failure: 0} = Oban.drain_queue(__MODULE__, queue: :posters)
    assert rows("SELECT count(*) FROM phoenix.cable_events") == [[3]]
    assert Processed.done?(ScratchRepo, args["event_id"])
    assert rows("SELECT kind FROM phoenix.rails_commands") == []

    rows(
      "INSERT INTO points (user_id,timestamp,lonlat,created_at,updated_at) VALUES($1,1774748800,ST_SetSRID(ST_MakePoint(13.4,0.00005),4326)::geography,now(),now())",
      [user.id]
    )

    for format <- ~w(json gpx) do
      {:ok, export} =
        PointExports.parse(%{
          "start_at" => "2026-03-29 00:00:00 UTC",
          "end_at" => "2026-03-30 00:00:00 UTC",
          "file_format" => format
        })

      assert {:ok, export_id} = PointExports.create(export, user, "de", ScratchRepo)

      assert [[2, %{"time_zone" => "America/New_York"}, scheduled]] =
               rows(
                 "SELECT command_version,payload,scheduled_at FROM job_outbox WHERE aggregate_id=$1 AND command_type='exports.points'",
                 [export_id]
               )

      assert %DateTime{} = scheduled

      assert %{dispatched: 1} =
               Dispatch.run(
                 now: Dawarich.JobsCase.db_now(ScratchRepo),
                 repo: ScratchRepo,
                 oban: __MODULE__
               )

      assert %{success: 1, failure: 0} =
               File.cd!(c.root, fn -> Oban.drain_queue(__MODULE__, queue: :exports) end)

      assert rows("SELECT status FROM exports WHERE id=$1", [export_id]) == [[2]]

      [[key]] =
        rows(
          "SELECT b.key FROM active_storage_blobs b JOIN active_storage_attachments a ON a.blob_id=b.id WHERE a.record_type='Export' AND a.record_id=$1",
          [export_id]
        )

      path = Path.join([c.root, "storage", String.slice(key, 0, 2), String.slice(key, 2, 2), key])
      assert {:ok, [{_, bytes}]} = :zip.unzip(to_charlist(path), [:memory])

      assert if(format == "json",
               do: length(Jason.decode!(bytes)["features"]) == 1,
               else: bytes =~ "<time>2026-03-28T21:46:40-04:00</time>"
             )
    end

    {:ok, archive} =
      PointExports.parse(%{
        "start_at" => "2026-03-29 00:00:00 UTC",
        "end_at" => "2026-03-30 00:00:00 UTC",
        "file_format" => "json"
      })

    assert {:ok, archive_id} =
             PointExports.create(%{archive | file_format: 2}, user, "en", ScratchRepo)

    due = DateTime.add(DateTime.utc_now(), 3600)
    PointExports.enqueue_created(ScratchRepo, archive_id, user, "en", DateTime.to_naive(due))

    assert [[^due]] =
             rows(
               "SELECT scheduled_at FROM job_outbox WHERE command_type='exports.points' AND aggregate_id=$1",
               [archive_id]
             )

    assert %{} = Dispatch.run(repo: ScratchRepo, oban: __MODULE__, now: DateTime.add(due, -1))
    assert %{dispatched: 1} = Dispatch.run(repo: ScratchRepo, oban: __MODULE__, now: due)

    assert %{success: 1, failure: 0} =
             File.cd!(c.root, fn -> Oban.drain_queue(__MODULE__, queue: :exports) end)

    assert rows("SELECT status,error_message FROM exports WHERE id=$1", [archive_id]) == [
             [3, "Unsupported file format: archive"]
           ]

    Ownership.put!(ScratchRepo, PurgeWorker.key(), :oban)
    old = video!(user.id, c.root, NaiveDateTime.add(now, -31 * 86_400))

    assert :ok =
             PurgeWorker.run(ScratchRepo, DateTime.from_naive!(now, "Etc/UTC"), %{
               retention_days: 30,
               max_per_user: 0
             })

    assert rows("SELECT status,settings FROM route_videos WHERE id=$1", [old]) == [
             [1, %{"source" => "trip"}]
           ]

    assert rows("SELECT record_id FROM active_storage_attachments WHERE record_type='RouteVideo'") ==
             []

    assert %{success: 1, failure: 0} =
             File.cd!(c.root, fn -> Oban.drain_queue(__MODULE__, queue: :exports) end)

    assert Path.wildcard(Path.join(c.root, "storage/vi/de/*")) == []
    assert rows("SELECT kind FROM phoenix.rails_commands") == []

    blank = video!(user.id, c.root, NaiveDateTime.add(now, -31 * 86_400))
    rows("UPDATE route_videos SET name='' WHERE id=$1", [blank])

    assert_raise RuntimeError, "route video name validation", fn ->
      PurgeWorker.run(ScratchRepo, DateTime.from_naive!(now, "Etc/UTC"), %{
        retention_days: 30,
        max_per_user: 0
      })
    end

    assert rows("SELECT status,expired_at FROM route_videos WHERE id=$1", [blank]) == [[0, nil]]

    assert rows("SELECT record_id FROM active_storage_attachments WHERE record_type='RouteVideo'") ==
             [[blank]]

    assert %{success: 0, failure: 0} =
             File.cd!(c.root, fn -> Oban.drain_queue(__MODULE__, queue: :exports) end)

    assert rows("SELECT kind FROM phoenix.rails_commands") == []
    assert source_queues() == c.source
  end

  @tag a12f3b_case: "E13b"
  test "E13 source accepted chain remains visible until all children settle", c do
    state = poster_fixture!()
    user = %{id: state["actor_id"]}
    id = state["before"]["id"]
    rows("DELETE FROM points")

    Command.produce(
      ScratchRepo,
      :oban,
      id,
      user,
      "de",
      NaiveDateTime.add(DateTime.to_naive(Dawarich.JobsCase.db_now(ScratchRepo)), -1)
    )

    assert %{dispatched: 1} =
             Dispatch.run(
               now: Dawarich.JobsCase.db_now(ScratchRepo),
               repo: ScratchRepo,
               oban: __MODULE__
             )

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(__MODULE__, queue: :posters, with_limit: 1)

    assert [["completed", %{"event_id" => event}]] =
             rows(
               "SELECT state,args FROM oban.oban_jobs WHERE worker='Dawarich.Posters.CreateWorker'"
             )

    assert Processed.done?(ScratchRepo, event)
    assert Drain.status(ScratchRepo).counts.incomplete_oban == 2
    assert "incomplete_oban" in Drain.status(ScratchRepo).shutdown_reasons
    assert %{success: 2, failure: 0} = Oban.drain_queue(__MODULE__, queue: :posters)
    rows("DELETE FROM posters WHERE id=$1", [id])

    blob = blob!(c.root)
    due = DateTime.add(DateTime.utc_now(), 3600)

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               Command.purge(ScratchRepo, :sidekiq, %{
                 "poster_id" => id,
                 "user_id" => user.id,
                 "blob_ids" => [blob]
               })
             end)

    assert [[child, %{"event_id" => continuation, "blob_ids" => [^blob]}]] =
             rows(
               "SELECT id,args FROM oban.oban_jobs WHERE worker='Dawarich.Posters.PurgeWorker'"
             )

    refute continuation == event
    rows("UPDATE oban.oban_jobs SET state='scheduled',scheduled_at=$2 WHERE id=$1", [child, due])
    assert Drain.status(ScratchRepo).counts.incomplete_oban == 1
    assert "incomplete_oban" in Drain.status(ScratchRepo).shutdown_reasons
    assert rows("SELECT kind FROM phoenix.rails_commands") == []
    assert %{success: 0, failure: 0} = Oban.drain_queue(__MODULE__, queue: :posters)

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(__MODULE__, queue: :posters, with_scheduled: due)

    assert Processed.done?(ScratchRepo, continuation)
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob]) == []
    assert Path.wildcard(Path.join(c.root, "storage/vi/de/*")) == []
    assert Drain.status(ScratchRepo).counts.incomplete_oban == 0
    refute "incomplete_oban" in Drain.status(ScratchRepo).shutdown_reasons

    for entry <- Registry.entries(),
        do: Ownership.put!(ScratchRepo, entry.key, :sidekiq, pinned: true)

    assert Drain.status(ScratchRepo).binary_rollback == "OBSERVED_EMPTY"
    assert rows("SELECT kind FROM phoenix.rails_commands") == []
    assert source_queues() == c.source
  end

  defp source_queues do
    uri = URI.parse(System.fetch_env!("PHOENIX_TEST_REDIS_URL"))
    {:ok, redis} = Redix.start_link(URI.to_string(%{uri | path: "/0"}))

    try do
      Redix.command!(redis, ["KEYS", "queue:*"])
      |> Map.new(fn key -> {key, Redix.command!(redis, ["LRANGE", key, "0", "-1"])} end)
    after
      GenServer.stop(redis)
    end
  end

  defp poster_fixture! do
    state = File.read!("test/fixtures/posters/points_gap_boundaries.json") |> Jason.decode!()

    rows(
      "INSERT INTO users(id,email,created_at,updated_at) VALUES($1,'media-source@dawarich.test',now(),now())",
      [state["actor_id"]]
    )

    for {table, data} <- [
          {"posters", [state["before"]]},
          {"points", state["points"]},
          {"tracks", state["tracks"]}
        ],
        row <- data do
      rows(
        "INSERT INTO #{table} SELECT * FROM json_populate_record(NULL::#{table},$1::text::json)",
        [Jason.encode!(row)]
      )
    end

    state
  end

  defp video!(user, root, created) do
    [[id]] =
      rows(
        "INSERT INTO route_videos(user_id,name,status,settings,created_at,updated_at) VALUES($1,'Synthetic video',0,'{\"source\":\"trip\"}',$2,$2) RETURNING id",
        [user, created]
      )

    blob = blob!(root)

    rows(
      "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','RouteVideo',$1,$2,now())",
      [id, blob]
    )

    id
  end

  defp blob!(root) do
    key = "video" <> Ecto.UUID.generate()
    path = Path.join([root, "storage", "vi", "de", key])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "synthetic video")

    [[id]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,created_at) VALUES($1,'synthetic.mp4','video/mp4','{}','local',15,now()) RETURNING id",
        [key]
      )

    id
  end
end
