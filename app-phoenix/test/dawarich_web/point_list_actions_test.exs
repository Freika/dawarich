defmodule DawarichWeb.PointListActionsTest do
  use Dawarich.IngestCase, async: false
  import Plug.Conn
  import Plug.Test
  import Dawarich.Test.RailsFormRequests, only: [upstream!: 0, forwarded: 2, rails_session: 1]
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  alias DawarichWeb.{MapWriteRequest, PointListActions, RailsAuth, RailsCsrf}

  setup do
    user = FrameSeeds.user!(91991, %{"timezone" => "UTC"}, %{plan: 0, status: 0, points_count: 2})
    FrameSeeds.point!(user.id, 919_910, 1_767_223_800)
    FrameSeeds.point!(user.id, 919_911, 1_791_021_600)
    upstream = upstream!()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})
    %{user: user, session: RailsUser.session(user.id), upstream: upstream}
  end

  defp request(ctx, method, path, suffix) do
    raw =
      "authenticity_token=" <>
        URI.encode_www_form(RailsCsrf.masked_token(ctx.session)) <> "&" <> suffix

    conn =
      method
      |> conn(path, raw)
      |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
      |> put_req_header("accept", "text/vnd.turbo-stream.html, text/html, application/xhtml+xml")
      |> RailsAuth.call([])
      |> MapWriteRequest.call([])

    {if(conn.halted, do: conn, else: PointListActions.call(conn, :destroy)), raw}
  end

  test "delete and override POST 303 preserve only Rails filters", ctx do
    path = "/points/bulk_destroy?start_at=query&order_by=desc&page=4"
    filters = "start_at=body&end_at=end&order_by=asc&import_id=17&page=9"

    for {method, prefix, id} <- [{:delete, "", 919_910}, {:post, "_method=delete&", 919_911}] do
      {response, _} = request(ctx, method, path, prefix <> filters <> "&point_ids[]=#{id}")
      assert response.status == 303

      assert get_resp_header(response, "location") == [
               "http://www.example.com/points?end_at=end&import_id=17&order_by=desc&start_at=query"
             ]

      assert rails_session(response)["flash"]["flashes"]["notice"] ==
               "Points were successfully destroyed."
    end

    assert Repo.query!("SELECT count(*) FROM points WHERE user_id=$1", [ctx.user.id]).rows == [
             [0]
           ]

    assert length(commands()) == 2
  end

  test "blank selection alerts unmatched nonblank succeeds without effects", ctx do
    for {suffix, kind, message} <- [
          {"point_ids[]=&point_ids[]=+&point_ids[]=%E3%80%80", "alert", "No points selected."},
          {"point_ids[]=919918", "notice", "Points were successfully destroyed."}
        ] do
      {response, _} = request(ctx, :delete, "/points/bulk_destroy", suffix)
      assert response.status == 303

      assert rails_session(response)["flash"] == %{
               "discard" => [],
               "flashes" => %{kind => message}
             }

      assert Repo.query!("SELECT points_count FROM users WHERE id=$1", [ctx.user.id]).rows == [
               [2]
             ]

      assert commands() == []
    end
  end

  test "unsupported query IDs forward raw without session changes", ctx do
    before = Repo.query!("SELECT id FROM points ORDER BY id").rows
    {probe, _} = request(ctx, :delete, "/points/bulk_destroy?locale=de", "point_ids[]=919910")
    assert probe.status == 502
    assert Repo.query!("SELECT id FROM points ORDER BY id").rows == before
    assert commands() == []
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, ctx.upstream.port})

    for {path, suffix} <- [
          {"/points/bulk_destroy?locale=de", "point_ids[]=919910"},
          {"/points/bulk_destroy", "point_ids[bad]=919910"},
          {"/points/bulk_destroy", "point_ids[]=919910&point_ids=919911"}
        ] do
      {{line, body}, {response, raw}} =
        forwarded(ctx.upstream, fn -> request(ctx, :delete, path, suffix) end)

      assert line == "DELETE #{path} HTTP/1.1"
      assert body == raw
      assert response.status == 204
      assert response.resp_cookies == %{}
      assert Repo.query!("SELECT id FROM points ORDER BY id").rows == before
      assert commands() == []
    end
  end
end
