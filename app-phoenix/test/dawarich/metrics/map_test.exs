defmodule Dawarich.Metrics.MapTest do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  alias Dawarich.Points.ApiPosition
  @moduletag :capture_log

  defmodule TimeoutRepo do
    def transaction(fun), do: Dawarich.Repo.transaction(fun, mode: :savepoint)
    def rollback(reason), do: Dawarich.Repo.rollback(reason)

    def query!(sql, args \\ []) do
      cancel =
        if Process.get(:map_cancel_after_lock),
          do: sql =~ "UPDATE points SET lonlat",
          else: sql =~ "FROM points" and sql =~ "FOR UPDATE"

      if cancel do
        Dawarich.Repo.query!(
          "DO $$ BEGIN RAISE EXCEPTION 'synthetic cancellation' USING ERRCODE='57014'; END $$"
        )
      else
        Dawarich.Repo.query!(sql, args)
      end
    end
  end

  defmodule FailedTiles do
    def fetch(_user, %{"fault" => code}) do
      Dawarich.Repo.transaction(
        fn ->
          Dawarich.Repo.query!(
            "DO $$ BEGIN RAISE EXCEPTION 'synthetic tile failure' USING ERRCODE='#{code}'; END $$"
          )
        end,
        mode: :savepoint
      )
    end
  end

  defmodule FailedEffectsRepo do
    def transaction(fun), do: Dawarich.Repo.transaction(fun)
    def rollback(reason), do: Dawarich.Repo.rollback(reason)

    def query!(sql, args \\ [], opts \\ []) do
      if sql =~ "INSERT INTO phoenix.rails_commands" and
           hd(args) == Process.get(:map_postcommit_fault) do
        raise "synthetic effect delivery failure"
      else
        Dawarich.Repo.query!(sql, args, opts)
      end
    end
  end

  setup do
    Dawarich.ApiEndpointCase.clear_transport_env()
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    start_supervised!(Dawarich.Metrics)
    url = Application.fetch_env!(:dawarich, :redis)[:url]
    start_supervised!({Redix, {url, [name: Dawarich.Cable.Bus.Publisher]}}, id: :publisher)
    actor = user!(%{settings: %{"timezone" => "UTC"}, plan: 1})

    user = %{
      id: actor,
      status: 1,
      plan: 1,
      active_until: nil,
      settings: %{"timezone" => "UTC"},
      timezone: "UTC"
    }

    handler = {__MODULE__, self()}

    :telemetry.attach_many(
      handler,
      [
        [:dawarich, :map, :move],
        [:dawarich, :map, :tile],
        [:dawarich, :map, :post_commit_failure]
      ],
      &__MODULE__.event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    %{user: user}
  end

  def event(event, measurements, metadata, pid),
    do: send(pid, {event, measurements, metadata})

  test "native moves and tiles retain map outcomes lock waits sizes and post commit failures", %{
    user: user
  } do
    [[track]] =
      rows(
        """
        INSERT INTO tracks(user_id,start_at,end_at,distance,duration,original_path,created_at,updated_at)
        VALUES($1,'2025-01-01','2025-01-01 00:02:00',100,120,
          ST_GeomFromText('LINESTRING(13 52,13.002 52)',4326),now(),now()) RETURNING id
        """,
        [user.id]
      )

    point = point!(user.id, track, 0)
    point!(user.id, track, 60)
    point!(user.id, track, 120)
    anomalous = point!(user.id, track, 180)
    rows("UPDATE points SET anomaly=true WHERE id=$1", [anomalous])

    for {from, to} <- [{0, 60}, {60, 120}] do
      rows(
        """
        INSERT INTO track_segments(track_id,start_at,end_at,start_index,end_index,created_at,updated_at)
        VALUES($1,to_timestamp($2),to_timestamp($3),$4,$5,now(),now())
        """,
        [track, 1_735_689_600 + from, 1_735_689_600 + to, div(from, 60), div(to, 60)]
      )
    end

    params = params(0) |> Map.put("track_revision", 0)
    ctx = %{self_hosted?: true, now: DateTime.utc_now()}
    assert {:ok, 200, _} = ApiPosition.update(Repo, user, point, params, ctx)
    assert_receive {[:dawarich, :map, :move], success, %{outcome: "success"}}
    assert success.count == 1
    assert success.duration > success.lock_wait and success.lock_wait > 0
    assert success.track_points == 3 and success.track_segments == 2
    assert {:error, 409, _} = ApiPosition.update(Repo, user, point, params, ctx)
    assert_receive {[:dawarich, :map, :move], conflict, %{outcome: "conflict"}}
    assert conflict.track_points == 1 and conflict.track_segments == 2
    assert conflict.lock_wait > 0

    untracked = point!(user.id, nil, 300)
    assert {:error, 422, _} = ApiPosition.update(TimeoutRepo, user, untracked, params(0), ctx)
    assert_receive {[:dawarich, :map, :move], timeout, %{outcome: "timeout"}}
    assert timeout.lock_wait == 0 and timeout.track_points == 1 and timeout.track_segments == 0
    assert rows("SELECT lock_version FROM points WHERE id=$1", [untracked]) == [[0]]

    Process.put(:map_cancel_after_lock, true)
    assert {:error, 422, _} = ApiPosition.update(TimeoutRepo, user, untracked, params(0), ctx)
    Process.delete(:map_cancel_after_lock)
    assert_receive {[:dawarich, :map, :move], locked_timeout, %{outcome: "timeout"}}
    assert locked_timeout.lock_wait > 0
    assert locked_timeout.track_points == 1 and locked_timeout.track_segments == 0
    assert rows("SELECT lock_version FROM points WHERE id=$1", [untracked]) == [[0]]

    assert {:error, 422, _} =
             ApiPosition.update(
               Repo,
               user,
               untracked,
               put_in(params(0), ["point", "latitude"], 91),
               ctx
             )

    assert {:error, 404, _} = ApiPosition.update(Repo, user, -1, params(0), ctx)
    refute_receive {[:dawarich, :map, :move], _, _}, 0

    stop_supervised!(:publisher)
    assert {:ok, 200, _} = ApiPosition.update(Repo, user, untracked, params(0), ctx)

    assert_receive {[:dawarich, :map, :post_commit_failure], %{count: 1},
                    %{operation: "broadcast"}}

    assert_receive {[:dawarich, :map, :move], plain, %{outcome: "success"}}
    assert plain.track_points == 1 and plain.track_segments == 0

    assert rows("SELECT lock_version,ST_Y(lonlat::geometry) FROM points WHERE id=$1", [untracked]) ==
             [[1, 52.0]]

    body = Dawarich.Metrics.scrape()

    for {outcome, count, samples} <- [
          {"success", 2, [success, plain]},
          {"conflict", 1, [conflict]},
          {"timeout", 2, [timeout, locked_timeout]}
        ] do
      assert body =~ ~s(dawarich_map_point_moves_total{outcome="#{outcome}"} #{count})

      for {family, measurement} <- [{"duration", :duration}, {"lock_wait", :lock_wait}] do
        assert sample(
                 body,
                 "dawarich_map_point_move_#{family}_seconds_count",
                 ~s(outcome="#{outcome}")
               ) == count

        expected =
          Enum.map(
            samples,
            &System.convert_time_unit(Map.fetch!(&1, measurement), :native, :nanosecond)
          )
          |> Enum.sum()
          |> Kernel./(1_000_000_000)

        assert_in_delta sample(
                          body,
                          "dawarich_map_point_move_#{family}_seconds_sum",
                          ~s(outcome="#{outcome}")
                        ),
                        expected,
                        1.0e-6
      end
    end

    assert sample(body, "dawarich_map_point_move_track_points_sum") == 7
    assert sample(body, "dawarich_map_point_move_track_segments_sum") == 4
    assert body =~ ~s(dawarich_map_post_commit_failures_total{operation="broadcast"} 1)

    for {operation, kind, revision} <- [
          {"publish", "points.tile_epoch", 1},
          {"stats", "stats.calculate_month", 2},
          {"achievements", "achievements.check", 3}
        ] do
      Process.put(:map_postcommit_fault, kind)

      try do
        assert {:ok, 200, _} =
                 ApiPosition.update(FailedEffectsRepo, user, untracked, params(revision), ctx)
      after
        Process.delete(:map_postcommit_fault)
      end

      assert_receive {[:dawarich, :map, :post_commit_failure], %{count: 1},
                      %{operation: ^operation}}

      assert_receive {[:dawarich, :map, :move], _, %{outcome: "success"}}
      assert rows("SELECT lock_version FROM points WHERE id=$1", [untracked]) == [[revision + 1]]

      assert Dawarich.Metrics.scrape() =~
               ~s(dawarich_map_post_commit_failures_total{operation="#{operation}"} 1)
    end

    tile_params = %{
      "z" => "10",
      "x" => "548",
      "y" => "338",
      "start_at" => "1735689600",
      "end_at" => "1735690100"
    }

    for {controller, layer} <- [
          {DawarichWeb.Api.PointTilesController, "point_tiles"},
          {DawarichWeb.Api.TrackTilesController, "track_tiles"}
        ] do
      first = controller.call(tile_conn(user, tile_params), :show)
      assert first.status == 200
      [etag] = get_resp_header(first, "etag")

      assert controller.call(
               tile_conn(user, tile_params) |> put_req_header("if-none-match", etag),
               :show
             ).status == 304

      assert controller.call(tile_conn(user, Map.put(tile_params, "import_id", "-1")), :show).status ==
               204

      assert controller.call(tile_conn(user, Map.put(tile_params, "z", "23")), :show).status ==
               400

      for {code, status} <- [{"57014", 503}, {"P0001", 500}] do
        response =
          Dawarich.Tiles.Http.call(
            tile_conn(user, Map.put(tile_params, "fault", code)),
            String.replace_suffix(layer, "_tiles", "s"),
            FailedTiles,
            1
          )

        assert response.status == status
        assert get_resp_header(response, "etag") == []
      end

      for {outcome, count} <- [
            {"success", 2},
            {"not_modified", 1},
            {"invalid", 1},
            {"failure", 1},
            {"http_500", 1}
          ] do
        samples =
          for _ <- 1..count do
            assert_receive {[:dawarich, :map, :tile], measurement,
                            %{layer: ^layer, outcome: ^outcome}}

            measurement
          end

        tags = ~s(layer="#{layer}",outcome="#{outcome}")
        body = Dawarich.Metrics.scrape()
        assert sample(body, "dawarich_map_tile_requests_total", tags) == count
        assert sample(body, "dawarich_map_tile_request_duration_seconds_count", tags) == count

        expected =
          Enum.map(samples, &System.convert_time_unit(&1.duration, :native, :nanosecond))
          |> Enum.sum()
          |> Kernel./(1_000_000_000)

        assert_in_delta sample(body, "dawarich_map_tile_request_duration_seconds_sum", tags),
                        expected,
                        1.0e-6
      end
    end

    buckets = %{
      "point_move_duration_seconds" => [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 3],
      "point_move_lock_wait_seconds" => [0.001, 0.005, 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 3],
      "point_move_track_points" => [1, 100, 1000, 10000, 50000, 100_000],
      "point_move_track_segments" => [0, 1, 5, 10, 25, 50, 100],
      "tile_request_duration_seconds" => [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 3, 5]
    }

    for metric <- Dawarich.Metrics.Map.definitions(),
        match?(%Telemetry.Metrics.Distribution{}, metric) do
      name = metric.name |> Enum.join(".") |> String.replace_prefix("dawarich_map_", "")
      assert metric.reporter_options[:buckets] == Map.fetch!(buckets, name)
    end

    refute Dawarich.Metrics.scrape() =~ "user_id="
    refute Dawarich.Metrics.scrape() =~ "point_id="
    assert_contended_lock(user, ctx)
  end

  defp assert_contended_lock(user, ctx) do
    repo = Dawarich.ScratchRepo
    Dawarich.JobsCase.reset!(repo)
    actor = Dawarich.Wave6Fixtures.user!(%{"settings" => %{"timezone" => "UTC"}})
    point = Dawarich.Wave6Fixtures.point!(actor, %{"timestamp" => 1_735_689_600})
    parent = self()

    locker =
      Task.async(fn ->
        repo.transaction(fn ->
          repo.query!("SELECT id FROM points WHERE id=$1 FOR UPDATE", [point])
          send(parent, :point_locked)
          receive do: (:release -> :ok)
        end)
      end)

    assert_receive :point_locked

    mover =
      Task.async(fn -> ApiPosition.update(repo, %{user | id: actor}, point, params(0), ctx) end)

    try do
      Dawarich.Wave6Fixtures.await_waiter!(
        "SELECT id FROM points WHERE id=%AND user_id=%FOR UPDATE"
      )

      blocked = System.monotonic_time()
      :erlang.yield()
      held = System.monotonic_time() - blocked
      send(locker.pid, :release)
      assert {:ok, 200, _} = Task.await(mover)
      assert_receive {[:dawarich, :map, :move], measurement, %{outcome: "success"}}
      assert measurement.lock_wait >= held and measurement.lock_wait > 0
      assert measurement.duration > measurement.lock_wait
      assert repo.query!("SELECT lock_version FROM points WHERE id=$1", [point]).rows == [[1]]
    after
      send(locker.pid, :release)
      Task.await(locker)
      Task.shutdown(mover)
      Dawarich.JobsCase.reset!(repo)
    end
  end

  defp point!(actor, track, offset) do
    [[id]] =
      rows(
        "INSERT INTO points(user_id,track_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,$3,ST_SetSRID(ST_MakePoint(13+$4::float8,52),4326),now(),now()) RETURNING id",
        [actor, track, 1_735_689_600 + offset, offset / 100_000]
      )

    id
  end

  defp params(revision),
    do: %{
      "point" => %{"latitude" => 52, "longitude" => 13.001, "revision" => revision},
      "history_scope" => %{"start_at" => "1735689600", "end_at" => "1735690100"}
    }

  defp tile_conn(user, params),
    do:
      Plug.Test.conn(:get, "/synthetic.mvt")
      |> assign(:api_user, user)
      |> assign(:api_params, params)

  defp sample(body, name, tags \\ "") do
    labels = if tags == "", do: "", else: "{" <> tags <> "}"
    [_, value] = Regex.run(~r/^#{Regex.escape(name <> labels)} ([^\n]+)$/m, body)
    {number, ""} = Float.parse(value)
    number
  end
end
