defmodule DawarichWeb.A12f3aVClosureTest do
  use Dawarich.JobsCase
  import Phoenix.ConnTest
  import Plug.Conn
  import Dawarich.Test.RailsFormRequests
  alias Dawarich.{Repo, ScratchRepo}
  alias Dawarich.Test.{RailsUser, ParityHTML}
  alias Dawarich.Visits.{WebDelete, WebBulk, WebMerge}
  alias DawarichWeb.RailsCsrf
  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    old_repo = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)
    on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, old_repo) end)
    for child <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(child)
    jwt = System.get_env("JWT_SECRET_KEY")
    System.put_env("JWT_SECRET_KEY", "a12f3a-visits-synthetic-jwt-secret-not-for-production")
    on_exit(fn -> env("JWT_SECRET_KEY", jwt) end)
    previous = System.get_env("SELF_HOSTED")
    on_exit(fn -> env("SELF_HOSTED", previous) end)
    :ok
  end

  @tag a12f3a_v01: true
  test "V01: visits legacy navigation matches current Rails contract without a native-owner Rails effect" do
    for mode <- ["true", "false", nil],
        method <- [:get, :head],
        status <- [nil, "", "suggested", "declined"] do
      env("SELF_HOSTED", mode)
      path = "/visits" <> if(is_nil(status), do: "", else: "?status=" <> status)
      conn = dispatch(build_conn(), @endpoint, method, path, nil)
      assert conn.status == 302

      assert get_resp_header(conn, "location") == [
               "http://www.example.com/map/v2?panel=timeline&date=today&status=" <>
                 (status || "confirmed")
             ]

      assert conn.resp_body == ""
      assert get_resp_header(conn, "set-cookie") == []
    end

    oracle = File.read!("test/fixtures/a8vv/visits/a12f3a-v01.json") |> Jason.decode!()
    assert oracle["status"] == 302
    assert oracle["location"] == "http://www.example.com/map/v2?panel=timeline&date=today&status="
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  @tag a12f3a_v02: true
  test "V02: single visit update and confirm matches current Rails contract without a native-owner Rails effect" do
    for {name, mode} <- [
          {"a12f3a-v02", "true"},
          {"rename", "false"},
          {"blank_name", nil},
          {"owned_place", "false"},
          {"demo_adoption", "true"}
        ] do
      env("SELF_HOSTED", mode)
      ctx = fixture(name)
      req = ctx.state["request"]
      conn = request(ctx, :patch, req["path"], req["params"], req["accept"])
      assert conn.status == ctx.state["status"]
      durable(ctx.state)

      assert ParityHTML.normalize(conn.resp_body) ==
               ParityHTML.normalize(File.read!("test/fixtures/a8vv/visits/#{name}.html"))

      no_rails()
    end
  end

  @tag a12f3a_v03: true
  test "V03: visit delete and source response matches current Rails contract without a native-owner Rails effect" do
    env("SELF_HOSTED", "false")
    ctx = fixture("a12f3a-v03")
    fixture("merge_noted")
    unrelated = rows("SELECT * FROM place_visits ORDER BY id")
    points = rows("SELECT id,visit_id,lock_version FROM points ORDER BY id")
    id = hd(ctx.state["before"]["rows"]["visits"])["id"]
    assert {:ok, result} = WebDelete.run(ScratchRepo, ctx.user, id, %{}, ctx)

    assert ParityHTML.normalize(DawarichWeb.VisitStreams.render(:destroy, result, ctx)) ==
             ParityHTML.normalize(File.read!("test/fixtures/a8vv/visits/soft_delete_turbo.html"))

    durable(ctx.state)
    assert rows("SELECT * FROM place_visits ORDER BY id") == unrelated
    assert rows("SELECT id,visit_id,lock_version FROM points ORDER BY id") == points
    no_rails()
    conn = request(ctx, :delete, "/visits/999999999", %{})
    assert conn.status == 404
    assert rows("SELECT * FROM place_visits ORDER BY id") == unrelated
  end

  @tag a12f3a_v04: true
  test "V04: bulk update scope and coercions matches current Rails contract without a native-owner Rails effect" do
    ctx = fixture("a12f3a-v04")
    req = ctx.state["request"]
    assert {:ok, result} = WebBulk.run(ScratchRepo, :update, ctx.user, req["params"], ctx)
    assert result.count == 1
    durable(ctx.state)
    no_rails()
    assert {:ok, [12]} = Dawarich.Visits.WebScope.ids("12,99")
    assert {:ok, [12, 99]} = Dawarich.Visits.WebScope.ids(["12", "12", "99", "no"])
    assert {:error, :too_many} = Dawarich.Visits.WebScope.ids(Enum.map(1..501, &to_string/1))
  end

  @tag a12f3a_v05: true
  test "V05: bulk destroy scope and rollback matches current Rails contract without a native-owner Rails effect" do
    ctx = fixture("a12f3a-v05")
    req = ctx.state["request"]
    assert {:ok, result} = WebBulk.run(ScratchRepo, :destroy, ctx.user, req["params"], ctx)
    durable(ctx.state)

    assert ParityHTML.normalize(DawarichWeb.VisitStreams.render(:bulk_destroy, result, ctx)) ==
             ParityHTML.normalize(
               File.read!("test/fixtures/a8vv/visits/bulk_cross_day_destroy.html")
             )

    no_rails()
    selected = fixture("bulk_date")

    sentinel =
      hd(selected.state["before"]["rows"]["visits"])
      |> Map.put("id", 909_010)
      |> Map.put("status", 1)

    ScratchRepo.query!(
      "INSERT INTO visits SELECT * FROM json_populate_record(NULL::visits,$1::text::json)",
      [Jason.encode!(sentinel)],
      log: false
    )

    ids =
      rows("SELECT id FROM visits WHERE user_id=$1 ORDER BY id", [selected.user.id])
      |> List.flatten()

    assert {:ok, %{count: 1}} =
             WebBulk.run(
               ScratchRepo,
               :destroy,
               selected.user,
               %{"source_status" => "suggested", "date" => "2026-10-03"},
               selected
             )

    assert rows("SELECT deleted_at IS NULL FROM visits WHERE id=ANY($1) ORDER BY id", [
             Enum.drop(ids, 1)
           ]) == [[true], [true]]
  end

  @tag a12f3a_v06: true
  test "V06: merge noted visits and same-day checks matches current Rails contract without a native-owner Rails effect" do
    ctx = fixture("a12f3a-v06")
    req = ctx.state["request"]
    assert {:ok, result} = WebMerge.run(ScratchRepo, ctx.user, req["params"]["visit_ids"], ctx)
    durable(ctx.state)
    assert rows("SELECT id FROM notes ORDER BY id") == []
    assert rows("SELECT id FROM place_visits ORDER BY id") == []
    assert rows("SELECT id FROM visits WHERE id=ANY($1)", [result.source_ids]) == []

    assert ParityHTML.normalize(DawarichWeb.VisitStreams.render(:merge, result, ctx)) ==
             ParityHTML.normalize(File.read!("test/fixtures/a8vv/visits/merge_noted.html"))

    no_rails()
  end

  @tag a12f3a_v07: true
  test "V07: visits settings page and writes matches current Rails contract without a native-owner Rails effect" do
    ctx = fixture("a12f3a-v07")

    for mode <- ["true", "false", nil] do
      env("SELF_HOSTED", mode)
      conn = RailsUser.signed_in(ctx.user.id) |> get("/settings/visits")
      assert conn.status == 200
      assert conn.resp_body =~ "phx-visit-detection-settings"

      for method <- [:patch, :put] do
        saved = request(ctx, method, "/settings/visits", ctx.state["params"], "text/html")
        assert saved.status == ctx.state["status"]
        assert get_resp_header(saved, "location") == [ctx.state["location"]]
        assert rails_session(saved)["flash"]["flashes"]["notice"] == ctx.state["flash"]["notice"]
        assert [[settings]] = rows("SELECT settings FROM users WHERE id=$1", [ctx.user.id])
        assert settings["visit_radius_meters"] == 75
        assert settings["unrelated"] == "survives"
      end
    end

    no_rails()
  end

  @tag a12f3a_v08: true
  test "V08: full-history and user redetect producer matches current Rails contract without a native-owner Rails effect" do
    env("SELF_HOSTED", "false")
    ctx = fixture("a12f3a-v08")
    conn = request(ctx, :post, "/visits/redetections", %{}, "text/html")
    assert conn.status == ctx.state["status"]
    assert get_resp_header(conn, "location") == [ctx.state["location"]]

    assert [[event, payload]] =
             rows(
               "SELECT event_id,payload FROM public.job_outbox WHERE command_type='visits.full_history_redetect'"
             )

    assert {:ok, args} = Dawarich.Visits.RedetectWorker.args_from_command(1, payload)
    no_rails()
    start_oban(__MODULE__.Oban)

    job = %Oban.Job{
      args: Map.put(args, "event_id", Ecto.UUID.cast!(event)),
      conf: Oban.config(__MODULE__.Oban)
    }

    assert Dawarich.Visits.RedetectWorker.perform(job) == :ok

    assert rows("SELECT title FROM notifications WHERE user_id=$1", [ctx.user.id]) == [
             ["Visit re-detection"]
           ]

    assert rows("SELECT visits_redetected_at FROM users WHERE id=$1", [ctx.user.id]) == [[nil]]
    pipeline = Dawarich.VisitsCase.load_visits!("detection_pipeline")
    uid = Dawarich.VisitsCase.user_id(pipeline)
    rows("UPDATE users SET visits_redetected_at=NULL,plan=1 WHERE id=$1", [uid])

    rows(
      "INSERT INTO areas(user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES($1,'Office',51.3397,12.3731,100,now(),now())",
      [uid]
    )

    for type <- ~w(visits.suggest visits.full_history_redetect places.delete_if_orphan) do
      Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:" <> type, :oban)
    end

    assert {:ok, _} =
             Dawarich.Visits.WebSettings.redetect(ScratchRepo, uid, DateTime.utc_now(), "en")

    [[root, accepted]] =
      rows(
        "SELECT event_id,payload FROM public.job_outbox WHERE command_type='visits.full_history_redetect' AND aggregate_id=$1",
        [uid]
      )

    root = Ecto.UUID.cast!(root)
    assert {:ok, start} = Dawarich.Visits.RedetectWorker.args_from_command(1, accepted)

    assert Dawarich.Visits.RedetectWorker.perform(%Oban.Job{
             args: Map.put(start, "event_id", root),
             conf: Oban.config(__MODULE__.Oban)
           }) == :ok

    [[child, child_args]] =
      rows(
        "SELECT id,args FROM oban.oban_jobs WHERE worker='Dawarich.Visits.RedetectWorker' AND args->>'event_id'=$1",
        [root]
      )

    assert child_args["step"] == 0
    assert child_args["event_id"] == root
    rows("DELETE FROM oban.oban_jobs WHERE id=$1", [child])

    assert Dawarich.Visits.RedetectWorker.perform(%Oban.Job{
             args: child_args,
             conf: Oban.config(__MODULE__.Oban)
           }) == :ok

    assert rows("SELECT visits_redetected_at IS NOT NULL FROM users WHERE id=$1", [uid]) == [
             [true]
           ]

    assert rows("SELECT title FROM notifications WHERE user_id=$1", [uid]) == [
             ["Visit re-detection complete"]
           ]

    assert rows("SELECT count(*) FROM visits WHERE user_id=$1", [uid]) == [[1]]
    no_rails()

    rows("UPDATE users SET visits_redetected_at=now() WHERE id=$1", [ctx.user.id])
    blocked = request(ctx, :post, "/visits/redetections", %{}, "text/html")
    assert blocked.status == 429
    assert get_resp_header(blocked, "location") == [ctx.state["location"]]

    assert rows(
             "SELECT count(*) FROM public.job_outbox WHERE command_type='visits.full_history_redetect' AND aggregate_id=$1",
             [ctx.user.id]
           ) == [[1]]

    no_rails()
  end

  @tag a12f3a_v09: true
  test "V09: visits native month and broadcast effects matches current Rails contract without a native-owner Rails effect" do
    ctx = fixture("a12f3a-v09")
    user = %{ctx.user | settings: Map.put(ctx.user.settings, "timezone", "")}
    rows("UPDATE users SET settings=$2 WHERE id=$1", [user.id, user.settings])
    ctx = %{ctx | user: user}

    keys =
      for month <- ~w(2026-09 2026-10 2026-11),
          segment <- ~w(lite pro),
          do: "timeline_month_summary/#{user.id}/#{month}/UTC/#{segment}/v3"

    on_exit(fn ->
      {:ok, cache} = Redix.start_link(System.fetch_env!("PHOENIX_TEST_REDIS_URL"), database: 0)
      Redix.command(cache, ["UNLINK" | keys])
      GenServer.stop(cache)
    end)

    for key <- keys,
        do: assert(Dawarich.RailsCache.put(key, "primed", expires_in: 300) == {:ok, "OK"})

    id = hd(ctx.state["before"]["rows"]["visits"])["id"]

    assert {:ok, result} =
             Dawarich.Visits.WebUpdate.run(
               ScratchRepo,
               user,
               id,
               ctx.state["request"]["params"]["visit"],
               ctx
             )

    assert [[args]] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [
               "Dawarich.Points.VisitMonthsWorker"
             ])

    assert :ok = Dawarich.Points.VisitMonthsWorker.run(ScratchRepo, args)

    for key <- keys do
      assert Dawarich.RailsCache.get(key) ==
               if(String.contains?(key, "/2026-11/"), do: {:ok, "primed"}, else: :miss)
    end

    no_rails()
    summary = Dawarich.Timeline.MonthSummary.build(user, "2026-10", nil, ctx.now, ScratchRepo)
    assert Enum.any?(List.flatten(summary.weeks), &(&1.visit_count == 1))
    assert result.old["started_at"].month == 9
    assert result.visit["started_at"].month == 10
  end

  defp fixture(name) do
    state = File.read!("test/fixtures/a8vv/visits/#{name}.json") |> Jason.decode!()
    u = hd(state["before"]["users"])

    actor =
      RailsUser.insert!(%{
        id: u["id"],
        email: u["email"],
        settings: u["settings"],
        api_key: u["api_key"],
        plan: u["plan"],
        visits_redetected_at:
          if(u["visits_redetected_at"],
            do: NaiveDateTime.from_iso8601!(u["visits_redetected_at"]),
            else: nil
          )
      })

    ScratchRepo.insert_all("users", [actor])

    for table <-
          ~w(places areas tags visits place_visits tracks track_segments points stats taggings notes),
        row <- Map.get(state["before"]["rows"] || %{}, table, []) do
      ScratchRepo.query!(
        "INSERT INTO #{table} SELECT * FROM json_populate_record(NULL::#{table}, $1::text::json)",
        [Jason.encode!(row)],
        log: false
      )
    end

    for type <- ~w(visits.suggest visits.full_history_redetect places.delete_if_orphan) do
      Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:" <> type, :oban)
    end

    {:ok, now, _} = DateTime.from_iso8601(state["now"])
    user = Dawarich.Accounts.get(actor.id)
    session = RailsUser.session(actor.id)

    %{
      user: user,
      now: now,
      self_hosted: state["self_hosted"],
      repo: ScratchRepo,
      locale: "en",
      csrf: "CSRF",
      state: state,
      session: session,
      token: RailsCsrf.masked_token(session)
    }
  end

  defp request(ctx, method, path, params, accept \\ "text/vnd.turbo-stream.html") do
    body = Plug.Conn.Query.encode(params)

    build_conn()
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("accept", accept)
    |> put_req_header("x-csrf-token", ctx.token)
    |> dispatch(@endpoint, method, path, body)
  end

  defp durable(state) do
    for expected <- state["after"]["rows"]["visits"] do
      actual =
        rows(
          "SELECT name,status,place_id,area_id,started_at,ended_at,duration,demo,deleted_at FROM visits WHERE id=$1",
          [expected["id"]]
        )

      values =
        Enum.map(~w(name status place_id area_id started_at ended_at duration demo deleted_at), fn
          key when key in ~w(started_at ended_at deleted_at) ->
            if expected[key],
              do: NaiveDateTime.from_iso8601!(expected[key]) |> Map.put(:microsecond, {0, 6}),
              else: nil

          key ->
            expected[key]
        end)

      assert actual == [values]
    end
  end

  defp no_rails, do: assert(rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]])

  defp env(key, nil), do: System.delete_env(key)
  defp env(key, value), do: System.put_env(key, value)
end
