defmodule DawarichWeb.VisitWritesRegressionTest do
  use Dawarich.JobsCase

  import Phoenix.ConnTest
  import Plug.Conn
  import Dawarich.Test.RailsFormRequests, only: [rails_session: 1]
  alias Dawarich.{Repo, ScratchRepo, RailsCache}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf
  @endpoint DawarichWeb.Endpoint
  @oban __MODULE__.Oban
  @worker "Dawarich.Points.VisitMonthsWorker"
  @tables ~w(places areas tags visits place_visits tracks track_segments points stats taggings notes)

  defmodule CommitRepo do
    defdelegate query!(sql, args, opts \\ []), to: Dawarich.ScratchRepo
    defdelegate insert!(changeset, opts), to: Dawarich.ScratchRepo
    defdelegate rollback(reason), to: Dawarich.ScratchRepo

    def transaction(fun) do
      Dawarich.ScratchRepo.transaction(fn ->
        result = fun.()

        if owner = Process.delete(:visit_commit_observer) do
          send(owner, {:before_visit_commit, self()})

          receive do
            :commit_visit -> :ok
          after
            5_000 -> raise "commit observer did not release transaction"
          end
        end

        result
      end)
    end
  end

  defmodule ExitRepo do
    def query!(_sql, _params, _opts), do: exit(:synthetic_connection_exit)
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous_repo = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)
    saved = Map.new(~w(SELF_HOSTED DAWARICH_RAILS), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "true")
    System.delete_env("DAWARICH_RAILS")
    start_oban(@oban)
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))

    on_exit(fn ->
      Application.put_env(:dawarich, :jobs_repo, previous_repo)
      for {key, value} <- saved, do: env(key, value)
    end)

    :ok
  end

  @tag :cache_outage
  test "visit write endpoints commit during cache outage and retry durable month invalidation" do
    stop_supervised(Dawarich.Redis.Cache)

    for mode <- [nil, "off"],
        action <- [:create, :update, :destroy, :merge, :bulk_update, :batch] do
      env("DAWARICH_RAILS", mode)
      reset!(ScratchRepo)
      ctx = fixture(if(action == :merge, do: "merge_points", else: "rename"))

      attrs = %{
        "name" => "API visit",
        "started_at" => "2026-10-02T12:00:00Z",
        "ended_at" => "2026-10-02T13:00:00Z",
        "latitude" => "10",
        "longitude" => "20"
      }

      {method, path, params, expected} =
        case action do
          :create ->
            {"POST", "/api/v1/visits", %{"visit" => attrs}, 200}

          :update ->
            {"PATCH", "/api/v1/visits/902000", %{"visit" => %{"name" => "API renamed"}}, 200}

          :destroy ->
            {"DELETE", "/api/v1/visits/902000", nil, 204}

          :merge ->
            {"POST", "/api/v1/visits/merge", ctx.request["params"], 200}

          :bulk_update ->
            {"POST", "/api/v1/visits/bulk_update",
             %{"visit_ids" => ["902000"], "status" => "confirmed"}, 200}

          :batch ->
            {"POST", "/api/v1/visits/batch", %{"visits" => [attrs]}, 200}
        end

      assert api_request(ctx, method, path, params).status == expected

      assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker=$1", [@worker]) != [[0]],
             inspect({mode, action})
    end

    for mode <- [nil, "off"],
        name <- ~w(rename soft_delete bulk_date bulk_cross_day_destroy merge_points) do
      env("DAWARICH_RAILS", mode)
      reset!(ScratchRepo)
      ctx = fixture(name)
      conn = request(ctx, ctx.request["method"], ctx.request["path"], ctx.request["params"])
      assert conn.status == 200
      assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker=$1", [@worker]) != [[0]]

      for expected <- ctx.state["after"]["rows"]["visits"] do
        assert rows("SELECT name,status FROM visits WHERE id=$1", [expected["id"]]) ==
                 [[expected["name"], expected["status"]]]
      end
    end

    assert %{snoozed: failed, success: 0} = Oban.drain_queue(@oban, queue: :projections)
    assert failed > 0

    assert [[id, "scheduled", 0, args]] =
             rows("SELECT id,state,attempt,args FROM oban.oban_jobs WHERE worker=$1", [@worker])

    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    key = month_key(args["user_id"], "2026-10", "Europe/Berlin", "pro")
    assert {:ok, "OK"} = RailsCache.put(key, "stale", expires_in: 300)
    assert :ok = Oban.retry_job(@oban, id)
    assert %{failure: 0, success: 1} = Oban.drain_queue(@oban, queue: :projections)
    assert RailsCache.get(key) == :miss

    assert rows("SELECT state,attempt FROM oban.oban_jobs WHERE id=$1", [id]) == [
             ["completed", 1]
           ]
  end

  @tag :commit_order
  test "committed visit writes fence month day and aggregate cache reads before worker execution" do
    ctx = fixture("a12f3a-v09")

    keys =
      for month <- ~w(2026-09 2026-10 2026-11),
          segment <- ~w(lite pro),
          do: month_key(ctx.user_id, month, "Europe/Berlin", segment)

    for key <- keys, do: assert({:ok, "OK"} = RailsCache.put(key, "primed", expires_in: 300))
    Application.put_env(:dawarich, :jobs_repo, CommitRepo)
    owner = self()
    before = rows("SELECT name,started_at FROM visits WHERE user_id=$1", [ctx.user_id])

    task =
      Task.async(fn ->
        Process.put(:visit_commit_observer, owner)
        request(ctx, ctx.request["method"], ctx.request["path"], ctx.request["params"])
      end)

    try do
      assert_receive {:before_visit_commit, pid}, 5_000
      assert rows("SELECT name,started_at FROM visits WHERE user_id=$1", [ctx.user_id]) == before
      assert rows("SELECT id FROM oban.oban_jobs WHERE worker=$1", [@worker]) == []
      for key <- keys, do: assert(RailsCache.get(key) == {:ok, "primed"})
      for key <- keys, do: RailsCache.put(key, "old committed snapshot", expires_in: 300)
      send(pid, :commit_visit)
      assert Task.await(task, 5_000).status == 200
    after
      send(task.pid, :commit_visit)
    end

    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)
    refute rows("SELECT name,started_at FROM visits WHERE user_id=$1", [ctx.user_id]) == before
    read = api_request(ctx, "GET", "/api/v1/visits/908000", nil)
    assert read.status == 200
    assert Jason.decode!(read.resp_body)["started_at"] =~ "2026-10-01"

    for key <- Enum.reject(keys, &String.contains?(&1, "/2026-11/")),
        do: assert(RailsCache.get(key) == :miss)

    assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :projections)

    for key <- keys do
      assert RailsCache.get(key) ==
               if(String.contains?(key, "/2026-11/"),
                 do: {:ok, "old committed snapshot"},
                 else: :miss
               )
    end

    generations = rows("SELECT key,token FROM phoenix.epochs ORDER BY key")
    jobs = rows("SELECT id FROM oban.oban_jobs WHERE worker=$1 ORDER BY id", [@worker])

    assert {:error, :rollback_probe} =
             ScratchRepo.transaction(fn ->
               Dawarich.Visits.Calendar.changed(ScratchRepo, ctx.user_id, [
                 ~U[2026-12-01 12:00:00Z]
               ])

               ScratchRepo.rollback(:rollback_probe)
             end)

    assert rows("SELECT key,token FROM phoenix.epochs ORDER BY key") == generations
    assert rows("SELECT id FROM oban.oban_jobs WHERE worker=$1 ORDER BY id", [@worker]) == jobs
  end

  @tag :unicode_merge
  test "visit merge endpoint folds Unicode names like Rails without a byte length limit" do
    ctx = fixture("merge_points")
    ids = ctx.request["params"]["visit_ids"] |> Enum.map(&String.to_integer/1)
    points = rows("SELECT id,user_id,timestamp,ST_AsText(lonlat) FROM points ORDER BY id")

    for {first, second, expected} <- [
          {"Café", " CAFÉ ", "Café"},
          {"東京", "公園", "東京, 公園"},
          {"İΣ", "i̇σ", "İΣ"},
          {"Café", "Café", "Café, Café"},
          {String.duplicate("é", 300), String.duplicate("É", 300), String.duplicate("é", 300)}
        ] do
      for row <- ctx.state["before"]["rows"]["visits"] do
        rows(
          "INSERT INTO visits SELECT * FROM json_populate_record(NULL::visits, $1::text::json) ON CONFLICT (id) DO NOTHING",
          [Jason.encode!(row)]
        )
      end

      rows("UPDATE visits SET name=$2,place_id=NULL WHERE id=$1", [hd(ids), first])
      rows("UPDATE visits SET name=$2,place_id=NULL WHERE id=$1", [List.last(ids), second])
      conn = request(ctx, "POST", "/visits/merge", %{"visit_ids" => Enum.map(ids, &to_string/1)})
      assert conn.status == 200

      assert rows("SELECT id,name,status FROM visits WHERE user_id=$1", [ctx.user_id]) ==
               [[hd(ids), expected, 1]]

      assert rows("SELECT id,user_id,timestamp,ST_AsText(lonlat) FROM points ORDER BY id") ==
               points
    end
  end

  @tag :invalid_place
  test "invalid place and area HTML visit updates redirect with the Rails alert" do
    ctx = fixture("rename")
    before = rows("SELECT row_to_json(v) FROM visits v WHERE user_id=$1", [ctx.user_id])

    for {field, message} <- [
          {"place_id", "Invalid place"},
          {"area_id", "Invalid area"}
        ],
        back <- [nil, "http://www.example.com/map/v2?date=2026-10-03&panel=timeline"] do
      headers = if back, do: [{"referer", back}], else: []

      conn =
        request(
          ctx,
          "PATCH",
          ctx.request["path"],
          %{"visit" => %{field => "999999999"}},
          "text/html",
          headers
        )

      assert conn.status == 302

      assert get_resp_header(conn, "location") == [
               back || "http://www.example.com/map/v2?date=today&panel=timeline"
             ]

      assert rails_session(conn)["flash"]["flashes"]["alert"] == message
      assert rows("SELECT row_to_json(v) FROM visits v WHERE user_id=$1", [ctx.user_id]) == before
    end
  end

  @tag :bulk_count
  test "over limit Turbo visit writes interpolate the maximum count in the flash" do
    ctx = fixture("rename")
    before = rows("SELECT row_to_json(v) FROM visits v WHERE user_id=$1", [ctx.user_id])

    for {method, path} <- [{"PATCH", "/visits/bulk_update"}, {"DELETE", "/visits/bulk_destroy"}] do
      conn =
        request(ctx, method, path, %{
          "visit_ids" => Enum.map(1..501, &to_string/1),
          "status" => "confirmed"
        })

      assert conn.status == 422

      assert conn.resp_body =~
               "You can update up to 500 visits at once. Narrow your selection and try again."

      refute conn.resp_body =~ "translation_missing"
      assert rows("SELECT row_to_json(v) FROM visits v WHERE user_id=$1", [ctx.user_id]) == before
    end
  end

  @tag :late_fill
  test "an old month snapshot filled after invalidation cannot resurrect stale day or aggregate counts" do
    for mode <- [nil, "off"], versioned <- [false, true] do
      env("DAWARICH_RAILS", mode)
      reset!(ScratchRepo)
      ctx = fixture("rename")

      if versioned do
        assert api_request(ctx, "PATCH", "/api/v1/visits/902000", %{
                 "visit" => %{"name" => "Earlier generation"}
               }).status == 200

        assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :projections)
      end

      key = month_key(ctx.user_id, "2026-10", "Europe/Berlin", "pro")
      physical = Dawarich.Visits.CacheGeneration.physical_key(key, ScratchRepo)
      assert {:ok, "OK"} = RailsCache.put(key, "old day and aggregate counts", expires_in: 300)
      assert {:ok, bytes} = Dawarich.Redis.cache_command(["GET", physical])

      assert api_request(ctx, "PATCH", "/api/v1/visits/902000", %{"visit" => %{"name" => "Fresh"}}).status ==
               200

      assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :projections)
      assert {:ok, "OK"} = Dawarich.Redis.cache_command(["SET", physical, bytes])
      assert RailsCache.get(key) == :miss
    end
  end

  @tag :api_bulk_intent
  test "API bulk status writes publish durable invalidation during cache outage" do
    stop_supervised!(Dawarich.Redis.Cache)

    for mode <- [nil, "off"] do
      env("DAWARICH_RAILS", mode)
      reset!(ScratchRepo)
      ctx = fixture("rename")

      assert api_request(ctx, "POST", "/api/v1/visits/bulk_update", %{
               "visit_ids" => ["902000"],
               "status" => "declined"
             }).status == 200

      assert rows("SELECT status FROM visits WHERE id=902000") == [[2]]
      assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker=$1", [@worker]) == [[1]]
    end
  end

  @tag :area_intent
  test "area deletion publishes durable visit invalidation during cache outage" do
    stop_supervised!(Dawarich.Redis.Cache)

    for mode <- [nil, "off"], demo <- [false, true] do
      env("DAWARICH_RAILS", mode)
      reset!(ScratchRepo)
      ctx = fixture("rename")

      [[area]] =
        rows(
          "INSERT INTO areas(user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES($1,'Review area',0,0,50,now(),now()) RETURNING id",
          [ctx.user_id]
        )

      rows("UPDATE visits SET area_id=$1,demo=$2 WHERE id=902000", [area, demo])

      assert {:ok, 200, _} =
               Dawarich.Areas.Api.destroy(
                 ScratchRepo,
                 Dawarich.Accounts.get(ctx.user_id),
                 area,
                 %{now: DateTime.utc_now(), self_hosted?: true}
               )

      assert rows("SELECT id FROM visits WHERE id=902000") == []
      assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker=$1", [@worker]) == [[1]]
    end
  end

  @tag :persistent_retry
  test "month invalidation survives more than three failures with backoff and recovers automatically" do
    ctx = fixture("rename")
    stop_supervised!(Dawarich.Redis.Cache)

    assert api_request(ctx, "PATCH", "/api/v1/visits/902000", %{
             "visit" => %{"name" => "Prolonged outage"}
           }).status == 200

    assert [[id]] = rows("SELECT id FROM oban.oban_jobs WHERE worker=$1", [@worker])

    for attempt <- 1..5 do
      if attempt > 1, do: assert(:ok = Oban.retry_job(@oban, id))
      Oban.drain_queue(@oban, queue: :projections)

      assert [["scheduled", 0, max_attempts, snoozed, seconds]] =
               rows(
                 "SELECT state,attempt,max_attempts,(meta->>'snoozed')::int,extract(epoch FROM scheduled_at-attempted_at)::float FROM oban.oban_jobs WHERE id=$1",
                 [id]
               )

      assert max_attempts > 0
      assert snoozed == attempt
      assert seconds >= 5 * Integer.pow(2, attempt - 1) and seconds <= 3601
    end

    rows("UPDATE oban.oban_jobs SET meta=jsonb_set(meta,'{snoozed}','100') WHERE id=$1", [id])
    assert :ok = Oban.retry_job(@oban, id)
    assert %{snoozed: 1, success: 0} = Oban.drain_queue(@oban, queue: :projections)

    assert [["scheduled", seconds]] =
             rows(
               "SELECT state,extract(epoch FROM scheduled_at-attempted_at)::float FROM oban.oban_jobs WHERE id=$1",
               [id]
             )

    assert seconds >= 3600 and seconds <= 3601
    assert rows("SELECT name FROM visits WHERE id=902000") == [["Prolonged outage"]]
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    assert :ok = Oban.retry_job(@oban, id)
    assert %{failure: 0, success: 1} = Oban.drain_queue(@oban, queue: :projections)

    assert rows("SELECT state,attempt FROM oban.oban_jobs WHERE id=$1", [id]) == [
             ["completed", 1]
           ]
  end

  @tag :retry_exit
  test "month invalidation connection exits retain durable recovery instead of exhausting attempts" do
    ctx = fixture("rename")

    assert api_request(ctx, "PATCH", "/api/v1/visits/902000", %{
             "visit" => %{"name" => "Connection exit probe"}
           }).status == 200

    Application.put_env(:dawarich, :jobs_repo, ExitRepo)
    assert %{snoozed: 1, success: 0} = Oban.drain_queue(@oban, queue: :projections)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)

    assert [[id, "scheduled", 1]] =
             rows("SELECT id,state,(meta->>'snoozed')::int FROM oban.oban_jobs WHERE worker=$1", [
               @worker
             ])

    assert :ok = Oban.retry_job(@oban, id)
    assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :projections)
  end

  @tag :ruby_mapping
  test "web and API merge retain names distinguished by Ruby 3.4.9 Unicode mappings" do
    for mode <- [nil, "off"],
        path <- ["/visits/merge", "/api/v1/visits/merge"],
        {first, second, expected} <- [
          {"Ɤ", "ɤ", "Ɤ, ɤ"},
          {"Ꟍ", "ꟍ", "Ꟍ, ꟍ"},
          {"Ᲊ", "ᲊ", "Ᲊ, ᲊ"},
          {"İΣ", "i̇σ", "İΣ"},
          {"Café", "Café", "Café, Café"},
          {"\u00a0X", "X", "\u00a0X, X"}
        ] do
      env("DAWARICH_RAILS", mode)
      reset!(ScratchRepo)
      ctx = fixture("merge_points")
      ids = Enum.map(ctx.request["params"]["visit_ids"], &String.to_integer/1)
      rows("UPDATE visits SET name=$2,place_id=NULL WHERE id=$1", [hd(ids), first])
      rows("UPDATE visits SET name=$2,place_id=NULL WHERE id=$1", [List.last(ids), second])
      params = %{"visit_ids" => Enum.map(ids, &to_string/1)}

      conn =
        if path == "/visits/merge",
          do: request(ctx, "POST", path, params),
          else: api_request(ctx, "POST", path, params)

      assert conn.status == 200
      assert rows("SELECT name FROM visits WHERE user_id=$1", [ctx.user_id]) == [[expected]]
    end
  end

  @tag :source_retry
  test "source owned visit writes retain a native cache retry alongside reverse compatibility commands" do
    ctx = fixture("rename")
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:visits.suggest", :sidekiq)
    stop_supervised!(Dawarich.Redis.Cache)

    assert api_request(ctx, "PATCH", "/api/v1/visits/902000", %{
             "visit" => %{"name" => "Source-owned write"}
           }).status == 200

    assert rows("SELECT count(*) FROM phoenix.rails_commands WHERE kind='visit_months_changed'") ==
             [[1]]

    assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker=$1", [@worker]) == [[1]]
    assert %{snoozed: 1, success: 0} = Oban.drain_queue(@oban, queue: :projections)
    assert rows("SELECT state FROM oban.oban_jobs WHERE worker=$1", [@worker]) == [["scheduled"]]
  end

  @tag :demo_api_intent
  test "demo API visit status and date writes invalidate calendar counts while preserving demo ownership" do
    stop_supervised!(Dawarich.Redis.Cache)

    for mode <- [nil, "off"],
        attrs <- [
          %{"status" => "confirmed"},
          %{"started_at" => "2026-11-03T10:00:00Z", "ended_at" => "2026-11-03T11:00:00Z"}
        ] do
      env("DAWARICH_RAILS", mode)
      reset!(ScratchRepo)
      ctx = fixture("rename")
      rows("UPDATE visits SET demo=true WHERE id=902000")
      assert api_request(ctx, "PATCH", "/api/v1/visits/902000", %{"visit" => attrs}).status == 200
      assert rows("SELECT demo FROM visits WHERE id=902000") == [[true]]
      assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker=$1", [@worker]) == [[1]]
    end
  end

  @tag :restore_intent
  test "user data restore publishes durable invalidation for inserted visit counts" do
    stop_supervised!(Dawarich.Redis.Cache)

    for mode <- [nil, "off"] do
      env("DAWARICH_RAILS", mode)
      reset!(ScratchRepo)
      ctx = fixture("rename")

      data = [
        %{
          "name" => "Restored count",
          "started_at" => "2026-10-04T12:00:00Z",
          "ended_at" => "2026-10-04T13:00:00Z",
          "duration" => 60,
          "status" => "suggested"
        }
      ]

      assert Dawarich.UserData.Restore.Visits.call(ScratchRepo, ctx.user_id, data, %{
               now: ~U[2026-10-05 00:00:00Z],
               repo: ScratchRepo
             }) == 1

      assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker=$1", [@worker]) == [[1]]
    end
  end

  @tag :demo_import_intent
  test "demo visit insertion publishes durable month invalidation during cache outage" do
    stop_supervised!(Dawarich.Redis.Cache)

    for mode <- [nil, "off"] do
      env("DAWARICH_RAILS", mode)
      reset!(ScratchRepo)
      ctx = fixture("rename")

      assert Dawarich.DemoData.Importer.call(
               ScratchRepo,
               Dawarich.Accounts.get(ctx.user_id),
               Dawarich.Test.DemoData.fixtures()
             ) == :created

      assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker=$1", [@worker]) == [[1]]
    end
  end

  @tag :demo_destroy_intent
  test "demo visit deletion publishes durable month invalidation during cache outage" do
    stop_supervised!(Dawarich.Redis.Cache)

    for mode <- [nil, "off"] do
      env("DAWARICH_RAILS", mode)
      reset!(ScratchRepo)
      ctx = fixture("rename")
      user = Dawarich.Accounts.get(ctx.user_id)

      assert Dawarich.DemoData.Importer.call(ScratchRepo, user, Dawarich.Test.DemoData.fixtures()) ==
               :created

      rows("DELETE FROM oban.oban_jobs WHERE worker=$1", [@worker])
      assert Dawarich.DemoData.Destroyer.call(ScratchRepo, user) == :destroyed
      assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker=$1", [@worker]) == [[1]]
    end
  end

  @tag :demo_cache_fence
  test "demo cache cleanup clears generated month entries for point-only affected months" do
    ctx = fixture("rename")

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               Dawarich.Visits.Calendar.changed(ScratchRepo, ctx.user_id, [
                 ~U[2026-10-03 12:00:00Z]
               ])
             end)

    assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :projections)
    key = month_key(ctx.user_id, "2026-10", "Europe/Berlin", "pro")
    assert {:ok, "OK"} = RailsCache.put(key, "point-only month counts", expires_in: 300)

    assert :ok =
             Dawarich.DemoData.Importer.invalidate(
               ScratchRepo,
               Dawarich.Accounts.get(ctx.user_id),
               [[2026, 10]]
             )

    assert RailsCache.get(key) == :miss
  end

  @tag :restore_native_owner
  test "native archive restore retains cache recovery without a reverse Rails command" do
    for native <- [false, true] do
      reset!(ScratchRepo)
      ctx = fixture("rename")
      Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:visits.suggest", :sidekiq)
      context = %{now: "2026-10-04T12:00:00Z", fence: fn fun -> fun.() end, native_owner: native}

      data = [
        %{
          "name" => "Native restore",
          "started_at" => "2026-10-04T12:00:00Z",
          "ended_at" => "2026-10-04T13:00:00Z",
          "duration" => 60,
          "status" => "suggested"
        }
      ]

      assert Dawarich.UserData.Restore.Visits.call(ScratchRepo, ctx.user_id, data, context) == 1
      assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker=$1", [@worker]) == [[1]]

      assert rows("SELECT count(*) FROM phoenix.rails_commands WHERE kind='visit_months_changed'") ==
               [[if(native, do: 0, else: 1)]]
    end
  end

  for {mode, label} <- [{nil, "coexistence"}, {"off", "standalone"}] do
    @tag :import_demo_intent
    test "import deletion fences restored demo visit counts after visible deletion in #{label}" do
      env("DAWARICH_RAILS", unquote(mode))
      ctx = fixture("rename")

      [[import_id]] =
        rows(
          "INSERT INTO imports(user_id,name,source,status,created_at,updated_at) VALUES($1,'demo.csv',10,2,now(),now()) RETURNING id",
          [ctx.user_id]
        )

      data = [
        %{
          "name" => "Imported demo visit",
          "started_at" => "2026-10-04T12:00:00Z",
          "ended_at" => "2026-10-04T13:00:00Z",
          "duration" => 60,
          "status" => "suggested",
          "demo" => true,
          "import_id" => import_id
        }
      ]

      assert Dawarich.UserData.Restore.Visits.call(ScratchRepo, ctx.user_id, data, %{
               now: ~U[2026-10-05 00:00:00Z],
               repo: ScratchRepo
             }) == 1

      [[visit_id, true]] = rows("SELECT id,demo FROM visits WHERE import_id=$1", [import_id])
      assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :projections)
      rows("DELETE FROM oban.oban_jobs WHERE worker=$1", [@worker])
      Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:imports.destroy", :oban)

      args = %{
        "import_id" => import_id,
        "user_id" => ctx.user_id,
        "event_id" => Ecto.UUID.generate()
      }

      [[job_id]] =
        rows(
          "INSERT INTO oban.oban_jobs(state,queue,worker,args,attempt,max_attempts,attempted_at) VALUES('executing','imports','Dawarich.Imports.DestroyWorker',$1,1,3,now()) RETURNING id",
          [args]
        )

      keys =
        for segment <- ~w(lite pro),
            do: month_key(ctx.user_id, "2026-10", "Europe/Berlin", segment)

      for key <- keys do
        assert {:ok, "OK"} = RailsCache.put(key, "old demo visit count", expires_in: 300)
      end

      stop_supervised!(Dawarich.Redis.Cache)

      assert :ok =
               Dawarich.Imports.DestroyWorker.perform(%Oban.Job{
                 id: job_id,
                 attempt: 1,
                 args: args
               })

      assert rows("SELECT id FROM visits WHERE id=$1", [visit_id]) == []
      start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
      for key <- keys, do: assert(RailsCache.get(key) == :miss)

      assert rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [@worker]) == [
               [%{"user_id" => ctx.user_id, "started_at" => ["2026-10-04T12:00:00.000000Z"]}]
             ]

      assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :projections)
      for key <- keys, do: assert(RailsCache.get(key) == :miss)
    end
  end

  defp fixture(name) do
    Dawarich.FixtureCleanup.delete!(ScratchRepo, @tables)
    state = File.read!("test/fixtures/a8vv/visits/#{name}.json") |> Jason.decode!()
    u = hd(state["before"]["users"])
    Repo.query!("DELETE FROM users WHERE id=$1", [u["id"]])

    actor =
      RailsUser.insert!(%{
        id: u["id"],
        email: u["email"],
        settings: u["settings"],
        plan: u["plan"],
        api_key: u["api_key"]
      })

    ScratchRepo.insert_all("users", [actor])

    for table <- @tables,
        row <- Map.get(state["before"]["rows"], table, []),
        do: insert_row(table, row)

    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:visits.suggest", :oban)
    session = RailsUser.session(actor.id)

    %{
      user_id: actor.id,
      api_key: actor.api_key,
      session: session,
      token: RailsCsrf.masked_token(session),
      state: state,
      request: state["request"]
    }
  end

  defp insert_row(table, row),
    do:
      rows(
        "INSERT INTO #{table} SELECT * FROM json_populate_record(NULL::#{table}, $1::text::json)",
        [Jason.encode!(row)]
      )

  defp request(ctx, method, path, params, accept \\ "text/vnd.turbo-stream.html", headers \\ []) do
    body = Plug.Conn.Query.encode(params)

    Enum.reduce(headers, build_conn(), fn {name, value}, conn ->
      put_req_header(conn, name, value)
    end)
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("accept", accept)
    |> put_req_header("x-csrf-token", ctx.token)
    |> dispatch(@endpoint, method, path, body)
  end

  defp api_request(ctx, method, path, params) do
    body = if params, do: Jason.encode!(params), else: ""

    build_conn()
    |> put_req_header("authorization", "Bearer " <> ctx.api_key)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("accept", "application/json")
    |> dispatch(@endpoint, method, path, body)
  end

  defp month_key(user, month, zone, segment),
    do: "timeline_month_summary/#{user}/#{month}/#{zone}/#{segment}/v3"

  defp env(key, nil), do: System.delete_env(key)
  defp env(key, value), do: System.put_env(key, value)
end
