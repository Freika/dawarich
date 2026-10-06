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
end
