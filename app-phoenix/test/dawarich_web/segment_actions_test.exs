defmodule DawarichWeb.SegmentActionsTest do
  use Dawarich.IngestCase, async: false
  import Plug.Conn
  import Plug.Test
  import Dawarich.Test.RailsFormRequests, only: [upstream!: 0, forwarded: 2, rails_session: 1]
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  alias DawarichWeb.{MapWriteRequest, RailsAuth, RailsCsrf, SegmentActions}

  setup do
    user =
      FrameSeeds.user!(
        91971,
        %{"timezone" => "UTC", "enabled_transportation_modes" => ~w(walking cycling driving)},
        %{status: 0, plan: 0}
      )

    FrameSeeds.track!(user.id, 919_710, %{
      start_at: ~N[2026-10-03 09:00:00],
      end_at: ~N[2026-10-03 09:10:00],
      dominant_mode: 4
    })

    seed_segment()
    upstream = upstream!()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})
    %{user: user, session: RailsUser.session(user.id), upstream: upstream}
  end

  defp seed_segment do
    FrameSeeds.segment!(919_710, 9_197_100, %{
      start_at: ~U[2026-10-03 09:00:00Z],
      end_at: ~U[2026-10-03 09:10:00Z],
      transportation_mode: 4,
      distance: 1000,
      duration: 600,
      corrected_at: ~N[2026-10-02 10:00:00],
      source: "user"
    })
  end

  defp request(
         ctx,
         method,
         suffix,
         accept \\ "text/vnd.turbo-stream.html, text/html, application/xhtml+xml",
         referer \\ nil
       ) do
    raw =
      "authenticity_token=" <>
        URI.encode_www_form(RailsCsrf.masked_token(ctx.session)) <> "&" <> suffix

    headers = [{"accept", accept}] ++ if(referer, do: [{"referer", referer}], else: [])

    conn =
      method
      |> conn("/tracks/919710/segments/9197100", raw)
      |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(raw)))

    conn =
      Enum.reduce(headers, conn, fn {key, value}, conn -> put_req_header(conn, key, value) end)

    result =
      conn
      |> RailsAuth.call([])
      |> MapWriteRequest.call([])
      |> assign(:now, ~U[2026-10-03 10:00:00.000000Z])
      |> SegmentActions.call(:update)

    {result, raw}
  end

  test "PATCH override POST call identical real override/reset", ctx do
    for method <- [:patch, :post] do
      if method == :post do
        Repo.query!("DELETE FROM track_segments WHERE track_id=919710")
        seed_segment()
      end

      prefix = if method == :post, do: "_method=patch&", else: ""
      {override, _} = request(ctx, method, prefix <> "track_segment[transportation_mode]=walking")
      assert override.status == 200

      assert get_resp_header(override, "content-type") == [
               "text/vnd.turbo-stream.html; charset=utf-8"
             ]

      assert override.resp_body =~ "segment-row-9197100"

      assert Repo.query!(
               "SELECT transportation_mode,corrected_at FROM track_segments WHERE id=9197100"
             ).rows == [[2, ~N[2026-10-03 10:00:00.000000]]]

      {literal, _} =
        request(ctx, method, prefix <> "reset=false&track_segment[transportation_mode]=driving")

      assert literal.status == 200

      assert Repo.query!("SELECT transportation_mode FROM track_segments WHERE id=9197100").rows ==
               [[5]]

      {reset, _} = request(ctx, method, prefix <> "reset=true")
      assert reset.status == 200
      assert reset.resp_body =~ "target=\"track-919710-segments\""
      assert Repo.query!("SELECT id FROM track_segments WHERE id=9197100").rows == []

      assert Repo.query!(
               "SELECT transportation_mode,source FROM track_segments WHERE track_id=919710"
             ).rows == [[0, "default"]]
    end
  end

  test "HTML success failure use referer root fallback and exact flash", ctx do
    for {referer, location, mode, kind, message} <- [
          {nil, "http://www.example.com/", "walking", "notice", "Segment updated"},
          {"http://www.example.com/points?order_by=asc",
           "http://www.example.com/points?order_by=asc", "driving", "notice", "Segment updated"},
          {nil, "http://www.example.com/", "flying", "alert",
           "That mode isn't enabled in your settings"}
        ] do
      {response, _} =
        request(ctx, :patch, "track_segment[transportation_mode]=#{mode}", "text/html", referer)

      assert response.status == 302
      assert get_resp_header(response, "location") == [location]

      assert rails_session(response)["flash"] == %{
               "discard" => [],
               "flashes" => %{kind => message}
             }
    end
  end

  test "unsupported referer replays before DML or flash", ctx do
    before = Repo.query!("SELECT to_jsonb(s)::text FROM track_segments s ORDER BY id").rows

    {probe, _} =
      request(
        ctx,
        :patch,
        "track_segment[transportation_mode]=walking",
        "text/html",
        "https://foreign.example.invalid/points"
      )

    assert probe.status == 502

    assert Repo.query!("SELECT to_jsonb(s)::text FROM track_segments s ORDER BY id").rows ==
             before

    assert commands() == []
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, ctx.upstream.port})

    for referer <- [
          "https://foreign.example.invalid/points",
          "//foreign.example.invalid/points",
          "/points\\bad"
        ] do
      {{line, body}, {response, raw}} =
        forwarded(ctx.upstream, fn ->
          request(ctx, :patch, "track_segment[transportation_mode]=walking", "text/html", referer)
        end)

      assert line == "PATCH /tracks/919710/segments/9197100 HTTP/1.1"
      assert body == raw
      assert response.status == 204
      assert response.resp_cookies == %{}

      assert Repo.query!("SELECT to_jsonb(s)::text FROM track_segments s ORDER BY id").rows ==
               before

      assert commands() == []
    end
  end
end
