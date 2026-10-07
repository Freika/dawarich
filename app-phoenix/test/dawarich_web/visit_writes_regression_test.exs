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

      if action != :bulk_update,
        do:
          assert(
            rows("SELECT count(*) FROM oban.oban_jobs WHERE worker=$1", [@worker]) != [[0]],
            inspect({mode, action})
          )
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

    assert %{failure: failed, success: 0} = Oban.drain_queue(@oban, queue: :projections)
    assert failed > 0

    assert [[id, "retryable", 1, args]] =
             rows("SELECT id,state,attempt,args FROM oban.oban_jobs WHERE worker=$1", [@worker])

    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    key = month_key(args["user_id"], "2026-10", "Europe/Berlin", "pro")
    assert {:ok, "OK"} = RailsCache.put(key, "stale", expires_in: 300)
    assert :ok = Oban.retry_job(@oban, id)
    assert %{failure: 0, success: 1} = Oban.drain_queue(@oban, queue: :projections)
    assert RailsCache.get(key) == :miss

    assert rows("SELECT state,attempt FROM oban.oban_jobs WHERE id=$1", [id]) == [
             ["completed", 2]
           ]
  end

  @tag :commit_order
  test "visit month invalidation runs after commit and clears a concurrent old snapshot fill" do
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
    assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :projections)

    for key <- keys do
      assert RailsCache.get(key) ==
               if(String.contains?(key, "/2026-11/"),
                 do: {:ok, "old committed snapshot"},
                 else: :miss
               )
    end
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
