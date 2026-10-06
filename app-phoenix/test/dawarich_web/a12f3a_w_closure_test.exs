defmodule DawarichWeb.A12f3aWClosureTest do
  use Dawarich.IngestCase, async: false
  import Plug.Conn
  import Plug.Test
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  alias Dawarich.Jobs.Ownership
  alias DawarichWeb.{RailsAuth, RailsCsrf, MapWriteRequest}

  setup do
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    user = FrameSeeds.user!(88101, %{"timezone" => "UTC"}, %{plan: 0, status: 0})
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})
    %{user: user, session: RailsUser.session(user.id), now: ~U[2026-10-03 10:00:00.000000Z]}
  end

  defp request(ctx, method, path, suffix, action, accept \\ "text/vnd.turbo-stream.html") do
    raw =
      "authenticity_token=" <>
        URI.encode_www_form(RailsCsrf.masked_token(ctx.session)) <> "&" <> suffix

    conn =
      method
      |> conn(path, raw)
      |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
      |> put_req_header("accept", accept)
      |> RailsAuth.call([])
      |> MapWriteRequest.call([])
      |> assign(:now, ctx.now)

    if conn.halted, do: conn, else: action.call(conn, :write)
  end

  defp outbox do
    Repo.query!(
      "SELECT command_type,payload,dedupe_key FROM public.job_outbox ORDER BY scheduled_at,(payload->>'track_id')::bigint,event_id"
    ).rows
  end

  @tag a12f3a_w10: true
  test "W10: area create and update forms matches current Rails contract without a native-owner Rails effect",
       ctx do
    Ownership.put!(Repo, "command:areas.relabel_visits", :oban)

    for method <- [:post, :patch, :put] do
      path = if method == :post, do: "/areas", else: "/areas/#{ctx.user.id}"

      if method == :post do
        response =
          request(
            ctx,
            method,
            path,
            "name=Leipzig+%3C%26%3E&latitude=51.34&longitude=12.37&radius=200",
            DawarichWeb.AreaActions
          )

        assert response.status == 200
        assert response.resp_body =~ "Area created successfully!"
        [[id]] = Repo.query!("SELECT id FROM areas WHERE user_id=$1", [ctx.user.id]).rows
        Repo.query!("UPDATE areas SET id=$2 WHERE id=$1", [id, ctx.user.id])
      else
        response =
          request(
            ctx,
            method,
            path,
            "name=Renamed&latitude=51.34&longitude=12.37&radius=300",
            DawarichWeb.AreaActions
          )

        assert response.status == 200
        assert response.resp_body =~ "Area updated successfully!"
      end
    end

    assert Repo.query!("SELECT name,radius FROM areas WHERE id=$1", [ctx.user.id]).rows == [
             ["Renamed", 300]
           ]

    before = Repo.query!("SELECT * FROM areas").rows

    response =
      request(
        ctx,
        :put,
        "/areas/#{ctx.user.id}",
        "name=&latitude=91&longitude=-181&radius=-1",
        DawarichWeb.AreaActions
      )

    assert response.status == 200
    assert response.resp_body =~ "Name can&#39;t be blank"
    assert Repo.query!("SELECT * FROM areas").rows == before
    foreign = FrameSeeds.user!(88102)

    Repo.query!(
      "INSERT INTO areas(id,user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES(88102,$1,'Other',51,12,100,$2,$2)",
      [foreign.id, DateTime.to_naive(ctx.now)]
    )

    denied = request(ctx, :patch, "/areas/88102", "name=Stolen", DawarichWeb.AreaActions)
    assert denied.status == 404
    assert Repo.query!("SELECT name FROM areas WHERE id=88102").rows == [["Other"]]
    assert commands() == []
  end

  @tag a12f3a_w11: true
  test "W11: area relabel producer matches current Rails contract without a native-owner Rails effect",
       ctx do
    Ownership.put!(Repo, "command:areas.relabel_visits", :oban)

    attrs = %{
      "name" => "Leipzig",
      "latitude" => "51.34",
      "longitude" => "12.37",
      "radius" => "200"
    }

    assert {:ok, %{area: area}} =
             Dawarich.Areas.WebWrite.create(Repo, ctx.user, attrs, %{now: ctx.now})

    assert [["areas.relabel_visits", %{"area_id" => id}, key]] = outbox()
    assert id == area.id
    assert key == to_string(id)
    Repo.query!("DELETE FROM public.job_outbox")

    assert {:ok, _} =
             Dawarich.Areas.WebWrite.update(Repo, ctx.user, id, %{"name" => "Renamed"}, %{
               now: ctx.now
             })

    assert outbox() == []

    assert {:ok, _} =
             Dawarich.Areas.WebWrite.update(
               Repo,
               ctx.user,
               id,
               attrs |> Map.put("radius", "300"),
               %{now: ctx.now}
             )

    assert length(outbox()) == 1

    assert {:ok, _} =
             Dawarich.Areas.WebWrite.update(Repo, ctx.user, id, %{"radius" => "300"}, %{
               now: ctx.now
             })

    assert length(outbox()) == 1
    assert commands() == []
  end

  @tag a12f3a_w13: true
  test "W13: user transportation reclassify worker matches current Rails contract without a native-owner Rails effect",
       ctx do
    Ownership.put!(Repo, "command:transportation.reclassify_track", :oban)
    foreign = FrameSeeds.user!(88102)

    for i <- 0..100,
        do:
          FrameSeeds.track!(ctx.user.id, 881_010 + i, %{
            start_at: NaiveDateTime.add(~N[2026-10-03 09:00:00], i),
            end_at: NaiveDateTime.add(~N[2026-10-03 09:10:00], i)
          })

    FrameSeeds.track!(foreign.id, 882_010, %{
      start_at: ~N[2026-10-04 09:00:00],
      end_at: ~N[2026-10-04 09:10:00]
    })

    event = Ecto.UUID.generate()
    args = %{"user_id" => ctx.user.id, "event_id" => event}
    assert :ok = Dawarich.Transportation.UserReclassify.run(Repo, args, %{now: ctx.now})
    children = outbox()
    assert length(children) == 101

    assert Enum.map(children, fn [_, payload, _] -> payload["track_id"] end) ==
             Enum.to_list(881_010..881_110)

    assert Enum.all?(children, fn [kind, payload, _] ->
             kind == "transportation.reclassify_track" and payload["report_progress"] and
               payload["user_id"] == ctx.user.id
           end)

    assert Repo.query!(
             "SELECT scheduled_at,count(*) FROM public.job_outbox GROUP BY scheduled_at ORDER BY scheduled_at"
           ).rows == [[ctx.now, 100], [DateTime.add(ctx.now, 10), 1]]

    assert Dawarich.Transportation.RecalculationStatus.data(ctx.user.id)["total_tracks"] == 101
    assert :ok = Dawarich.Transportation.UserReclassify.run(Repo, args, %{now: ctx.now})
    assert outbox() == children

    assert :ok =
             Dawarich.Transportation.UserReclassify.run(
               Repo,
               %{"user_id" => foreign.id, "event_id" => Ecto.UUID.generate()},
               %{now: ctx.now}
             )

    assert commands() == []

    [[raw_event, payload]] =
      Repo.query!(
        "SELECT event_id,payload FROM public.job_outbox WHERE payload->>'track_id'='881010'"
      ).rows

    child_event = Ecto.UUID.cast!(raw_event)

    assert :ok =
             Dawarich.Transportation.ReclassifyTrackWorker.run(
               Repo,
               Oban,
               Map.put(payload, "event_id", child_event)
             )

    assert Dawarich.Transportation.RecalculationStatus.data(ctx.user.id)["processed_tracks"] == 1
    assert :ok = Dawarich.Transportation.RecalculationStatus.increment(ctx.user.id, child_event)
    assert Dawarich.Transportation.RecalculationStatus.data(ctx.user.id)["processed_tracks"] == 1

    for i <- 1..100,
        do: Dawarich.Transportation.RecalculationStatus.increment(ctx.user.id, "remaining-#{i}")

    assert Dawarich.Transportation.RecalculationStatus.data(ctx.user.id)["status"] == "completed"
    refute Enum.any?(commands(), fn [kind, _] -> kind == "transport_progress" end)
    Repo.query!("DELETE FROM public.job_outbox")

    assert_raise RuntimeError, "synthetic fanout failure", fn ->
      Dawarich.Transportation.UserReclassify.run(
        Repo,
        %{"user_id" => ctx.user.id, "event_id" => Ecto.UUID.generate()},
        %{now: ctx.now, before_enqueue: fn -> raise "synthetic fanout failure" end}
      )
    end

    assert outbox() == []
    assert Dawarich.Transportation.RecalculationStatus.data(ctx.user.id)["status"] == "failed"

    assert Dawarich.Transportation.RecalculationStatus.data(ctx.user.id)["error_message"] ==
             "synthetic fanout failure"

    Dawarich.Transportation.RecalculationStatus.clear(ctx.user.id)
    Dawarich.Transportation.RecalculationStatus.clear(foreign.id)
  end

  @tag a12f3a_w12: true
  test "W12: track recalculation request matches current Rails contract without a native-owner Rails effect",
       ctx do
    Ownership.put!(Repo, "command:transportation.user_reclassify", :oban)
    Dawarich.Transportation.RecalculationStatus.clear(ctx.user.id)

    response =
      request(ctx, :post, "/tracks/recalculation", "", DawarichWeb.TrackRecalculationActions)

    assert response.status == 200
    assert response.resp_body =~ "Re-classification started"
    assert [["transportation.user_reclassify", %{"user_id" => id}, _]] = outbox()
    assert id == ctx.user.id
    Dawarich.Transportation.RecalculationStatus.start(ctx.user.id, 2, ctx.now)

    running =
      request(ctx, :post, "/tracks/recalculation", "", DawarichWeb.TrackRecalculationActions)

    assert running.status == 200
    assert running.resp_body =~ "already running"
    assert length(outbox()) == 1
    assert commands() == []
    Dawarich.Transportation.RecalculationStatus.clear(ctx.user.id)
  end

  @tag a12f3a_w04: true
  test "W04: point delete follow-up effects matches current Rails contract without a native-owner Rails effect",
       ctx do
    for key <- ~w(stats.calculate_month tracks.recalculate achievements.check),
        do: Ownership.put!(Repo, "command:" <> key, :oban)

    FrameSeeds.track!(ctx.user.id, 881_010, %{
      start_at: ~N[2026-10-03 09:00:00],
      end_at: ~N[2026-10-03 09:10:00]
    })

    FrameSeeds.point!(ctx.user.id, 881_010, 1_791_018_000)
    Repo.query!("UPDATE points SET track_id=881010 WHERE id=881010")

    assert {:ok, %{deleted: [%{id: 881_010}]}} =
             Dawarich.Points.WebDestroy.run(Repo, ctx.user, ["881010", "881010"], %{
               locale: "en",
               timezone: "UTC",
               now: ctx.now
             })

    assert [["points.tile_epoch", %{"user_id" => user_id, "timestamps" => [1_791_018_000]}]] =
             commands()

    assert user_id == ctx.user.id

    assert Enum.sort(Enum.map(outbox(), &hd/1)) ==
             ~w(achievements.check stats.calculate_month tracks.recalculate)

    assert Enum.find(outbox(), &(hd(&1) == "stats.calculate_month")) |> Enum.at(1) == %{
             "user_id" => ctx.user.id,
             "year" => 2026,
             "month" => 10,
             "notify_on_failure" => true
           }

    assert Repo.query!("SELECT count(*) FROM points WHERE id=881010").rows == [[0]]
  end

  @tag a12f3a_w03: true
  test "W03: point bulk-delete request and coercions matches current Rails contract without a native-owner Rails effect",
       ctx do
    FrameSeeds.point!(ctx.user.id, 881_010, 1_700_000_000)

    scalar =
      request(
        ctx,
        :delete,
        "/points/bulk_destroy",
        "point_ids=881010",
        DawarichWeb.PointListActions,
        "text/html"
      )

    assert scalar.status == 500
    assert Repo.query!("SELECT id FROM points WHERE id=881010").rows == [[881_010]]
    foreign = FrameSeeds.user!(88102)
    FrameSeeds.point!(foreign.id, 882_010, 1_791_018_000)

    deleted =
      request(
        ctx,
        :post,
        "/points/bulk_destroy",
        "_method=delete&point_ids[]=881010&point_ids[]=881010&point_ids[]=882010",
        DawarichWeb.PointListActions,
        "text/html"
      )

    assert deleted.status == 303
    assert Repo.query!("SELECT id FROM points ORDER BY id").rows == [[882_010]]
  end

  @tag a12f3a_w08: true
  test "W08: segment index and direct put matches current Rails contract without a native-owner Rails effect",
       ctx do
    user = %{
      ctx.user
      | settings: %{"timezone" => "UTC", "enabled_transportation_modes" => ~w(walking cycling)}
    }

    Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [user.id, user.settings])

    for id <- [881_010, 881_011] do
      FrameSeeds.track!(user.id, id, %{
        start_at: NaiveDateTime.add(~N[2026-10-03 09:00:00], id - 881_010),
        end_at: NaiveDateTime.add(~N[2026-10-03 09:10:00], id - 881_010)
      })

      FrameSeeds.segment!(id, id * 10, %{
        start_at: ~U[2026-10-03 09:00:00Z],
        end_at: ~U[2026-10-03 09:10:00Z],
        distance: 1000,
        duration: 600,
        transportation_mode: 4
      })
    end

    response =
      request(
        ctx,
        :put,
        "/tracks/881010/segments/8810100",
        "track_segment[transportation_mode]=walking",
        DawarichWeb.SegmentActions
      )

    assert response.status == 200
    assert response.resp_body =~ "segment-row-8810100"

    assert Repo.query!(
             "SELECT transportation_mode,source,confidence FROM track_segments WHERE id=8810100"
           ).rows == [[2, "user", 2]]

    wrong =
      request(
        ctx,
        :put,
        "/tracks/881010/segments/8810110",
        "track_segment[transportation_mode]=walking",
        DawarichWeb.SegmentActions
      )

    assert wrong.status == 404

    assert Repo.query!("SELECT transportation_mode FROM track_segments WHERE id=8810110").rows ==
             [[4]]
  end

  @tag a12f3a_w02: true
  test "W02: point address direct and framed matches current Rails contract without a native-owner Rails effect",
       ctx do
    FrameSeeds.point!(ctx.user.id, 881_010, 1_791_018_000)

    Repo.query!("UPDATE points SET geodata=$2 WHERE id=$1", [
      881_010,
      %{"properties" => %{"street" => "Straße <&>", "city" => "Leipzig"}}
    ])

    foreign = FrameSeeds.user!(88102)
    FrameSeeds.point!(foreign.id, 882_010, 1_791_018_000)

    for frame <- [nil, "point-address-881010"] do
      conn =
        conn(:get, "/points/881010/address")
        |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
        |> RailsAuth.call([])

      conn = if frame, do: put_req_header(conn, "turbo-frame", frame), else: conn
      response = DawarichWeb.PointAddress.call(conn, :address)
      assert response.status == 200
      assert response.resp_body =~ "point-address-881010"
      assert response.resp_body =~ "Straße &lt;&amp;&gt;"
      if is_nil(frame), do: assert(response.resp_body =~ "<!DOCTYPE html>")
    end

    conn =
      conn(:get, "/points/882010/address")
      |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
      |> RailsAuth.call([])

    assert DawarichWeb.PointAddress.call(conn, :address).status == 404

    for id <- ["no", "999999", "99999999999999999999999999999"] do
      conn =
        conn(:get, "/points/#{id}/address")
        |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
        |> RailsAuth.call([])

      assert DawarichWeb.PointAddress.call(conn, :address).status == 404
      assert DawarichWeb.MapDataGate.point_address?(conn, %{"id" => id})
    end

    assert commands() == []
  end

  @tag a12f3a_w05: true
  test "W05: tag pages and scope matches current Rails contract without a native-owner Rails effect",
       ctx do
    foreign = FrameSeeds.user!(88102)
    FrameSeeds.place!(foreign.id, 882_010, "Other")
    FrameSeeds.tag!(foreign.id, 882_010, "Private", 882_010, ~N[2026-10-03 09:00:00])
    assert Dawarich.TagPages.index(ctx.user) == []
    assert Dawarich.TagPages.edit(ctx.user, 882_010) == :not_found
    assert Dawarich.TagPages.edit(ctx.user, 999_999) == :not_found
    assert {:ok, %{name: "Private"}} = Dawarich.TagPages.edit(foreign, 882_010)
  end

  @tag a12f3a_w07: true
  test "W07: tag update and delete matches current Rails contract without a native-owner Rails effect",
       ctx do
    FrameSeeds.place!(ctx.user.id, 881_010, "Home")
    FrameSeeds.tag!(ctx.user.id, 881_010, "Home", 881_010, ~N[2026-10-03 09:00:00])

    assert request(
             ctx,
             :put,
             "/tags/881010",
             "tag[name]=Renamed",
             DawarichWeb.TagActions,
             "text/html"
           ).status == 302

    assert request(ctx, :delete, "/tags/881010", "", DawarichWeb.TagActions, "text/html").status ==
             303

    assert Repo.query!("SELECT count(*) FROM taggings WHERE tag_id=881010").rows == [[0]]
    assert Repo.query!("SELECT count(*) FROM places WHERE id=881010").rows == [[1]]

    assert request(ctx, :delete, "/tags/881010", "", DawarichWeb.TagActions, "text/html").status ==
             404
  end

  @tag a12f3a_w06: true
  test "W06: tag create and validation matches current Rails contract without a native-owner Rails effect",
       ctx do
    invalid =
      request(
        ctx,
        :post,
        "/tags",
        "tag[name]=Leipzig&tag[privacy_radius_meters]=-1",
        DawarichWeb.TagActions,
        "text/html"
      )

    assert invalid.status == 422
    assert Repo.query!("SELECT count(*) FROM tags WHERE user_id=$1", [ctx.user.id]).rows == [[0]]
    missing = request(ctx, :post, "/tags", "", DawarichWeb.TagActions, "text/html")
    assert missing.status == 400

    assert request(ctx, :post, "/tags", "tag=++", DawarichWeb.TagActions, "text/html").status ==
             400

    assert request(ctx, :post, "/tags", "tag=scalar", DawarichWeb.TagActions, "text/html").status ==
             500

    assert commands() == []
  end

  @tag a12f3a_w01: true
  test "W01: point list residual reads matches current Rails contract without a native-owner Rails effect",
       ctx do
    for id <- [881_010, 881_011] do
      FrameSeeds.point!(ctx.user.id, id, 1_791_018_000)

      Repo.query!("UPDATE points SET lonlat=ST_GeogFromText($2) WHERE id=$1", [
        id,
        "POINT(#{12.37 + (id - 881_010) * 0.01} 51.34)"
      ])
    end

    Repo.query!(
      "INSERT INTO imports(id,user_id,name,created_at,updated_at) VALUES(881010,$1,'Selected',$2,$2),(881011,$1,'Other',$2,$2)",
      [ctx.user.id, DateTime.to_naive(ctx.now)]
    )

    Repo.query!("UPDATE points SET import_id=id WHERE user_id=$1", [ctx.user.id])

    assert {:ok, page} =
             Dawarich.PointList.load(
               ctx.user,
               %{"start_at" => "1791010000", "end_at" => "1791020000"},
               ctx.now,
               self_hosted: true
             )

    assert Enum.sort(Enum.map(page.rows, & &1.id)) == [881_010, 881_011]

    assert {:ok, filtered} =
             Dawarich.PointList.load(ctx.user, %{"import_id" => "881010"}, ctx.now,
               self_hosted: true
             )

    assert Enum.map(filtered.rows, & &1.id) == [881_010]

    for value <- ["missing", "999999", "-1"] do
      assert Dawarich.PointList.load(ctx.user, %{"import_id" => value}, ctx.now,
               self_hosted: true
             ) == :not_found
    end

    assert {:ok, prefix} =
             Dawarich.PointList.load(ctx.user, %{"import_id" => "881010abc"}, ctx.now,
               self_hosted: true
             )

    assert Enum.map(prefix.rows, & &1.id) == [881_010]
    assert commands() == []
  end
end
