defmodule DawarichWeb.MapWriteRequestTest do
  use Dawarich.IngestCase, async: false

  import Plug.Conn
  import Plug.Test
  import Dawarich.Test.RailsFormRequests, only: [upstream!: 0, forwarded: 2]

  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{MapWriteRequest, RailsAuth, RailsCsrf}

  setup do
    actor =
      RailsUser.insert!(%{id: 9182, email: "a6s4-write@example.invalid", status: 0, plan: 0})

    session = RailsUser.session(actor.id)
    upstream = upstream!()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})
    %{session: session, token: RailsCsrf.masked_token(session), upstream: upstream}
  end

  defp request(ctx, method, path, body, headers \\ []) do
    method
    |> conn(path, body)
    |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("accept", "text/html, application/xhtml+xml")
    |> put_req_header("origin", "http://www.example.com")
    |> then(fn conn ->
      Enum.reduce(headers, conn, fn {key, value}, conn -> put_req_header(conn, key, value) end)
    end)
    |> RailsAuth.call([])
    |> MapWriteRequest.call([])
  end

  defp body(ctx, suffix),
    do: "authenticity_token=" <> URI.encode_www_form(ctx.token) <> "&" <> suffix

  defp replay(ctx, method, path, body, headers \\ []) do
    before = snapshot()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, ctx.upstream.port})

    {{line, raw}, conn} =
      forwarded(ctx.upstream, fn -> request(ctx, method, path, body, headers) end)

    assert conn.status == 204
    assert conn.halted
    assert line == "#{method |> Atom.to_string() |> String.upcase()} #{path} HTTP/1.1"
    assert raw == body
    assert snapshot() == before
    assert commands() == []
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})
  end

  defp snapshot do
    Repo.query!(
      "SELECT (SELECT count(*) FROM tags), (SELECT count(*) FROM track_segments), (SELECT count(*) FROM points)"
    ).rows
  end

  test "nested fields repeated point IDs and effective methods match Rails", ctx do
    for {method, path, suffix, action, effective} <- [
          {:patch, "/tracks/42/segments/43", "track_segment[transportation_mode]=walking",
           :segment_update, "PATCH"},
          {:post, "/tracks/42/segments/43", "_method=patch&reset=true", :segment_update, "PATCH"},
          {:delete, "/points/bulk_destroy", "point_ids[]=&point_ids[]=42&point_ids[]=42",
           :point_destroy, "DELETE"},
          {:post, "/points/bulk_destroy", "_method=delete&point_ids[]=42", :point_destroy,
           "DELETE"}
        ] do
      raw = body(ctx, suffix)
      conn = request(ctx, method, path, raw)
      refute conn.halted
      assert conn.assigns.map_write_action == action
      assert conn.assigns.map_write_method == effective
      refute Map.has_key?(conn.assigns.api_params, "_method")
      assert conn.private.dawarich_raw_body == raw
    end

    conn =
      request(
        ctx,
        :delete,
        "/points/bulk_destroy",
        body(ctx, "point_ids[]=&point_ids[]=42&point_ids[]=42")
      )

    assert conn.assigns.api_params["point_ids"] == ["", "42", "42"]
    assert snapshot() == [[0, 0, 0]]
    assert commands() == []
  end

  test "ambiguous headers session tokens origin and writers replay raw", ctx do
    raw = body(ctx, "_method=patch&track_segment[transportation_mode]=walking")

    rejected =
      request(ctx, :post, "/tracks/42/segments/43", raw, [{"origin", "http://foreign.test"}])

    assert rejected.halted
    replay(ctx, :post, "/tracks/42/segments/43", raw, [{"origin", "http://foreign.test"}])
    replay(%{ctx | session: %{}}, :post, "/tracks/42/segments/43", raw)

    replay(
      ctx,
      :post,
      "/tracks/42/segments/43",
      "_method=patch&track_segment[transportation_mode]=walking&authenticity_token=invalid"
    )

    per_form = RailsCsrf.masked_form_token(ctx.session, "/tracks/42/segments/43", "post")

    replay(
      ctx,
      :post,
      "/tags",
      "_method=patch&track_segment[transportation_mode]=walking&authenticity_token=" <>
        URI.encode_www_form(per_form)
    )

    replay(ctx, :post, "/tracks/42/segments/43", raw, [{"x-http-method-override", "POST"}])
    replay(ctx, :post, "/tracks/42/segments/43", raw, [{"x_csrf_token", "ambiguous"}])
    replay(ctx, :post, "/tracks/42/segments/43", raw, [{"x-dawarich-client", "synthetic"}])

    for key <- ~w(locale client aff via) do
      replay(ctx, :post, "/tracks/42/segments/43", raw <> "&#{key}=value")
    end

    cookie = RailsUser.cookie(ctx.session)

    replay(ctx, :post, "/tracks/42/segments/43", raw, [
      {"cookie", "_dawarich_session=#{cookie}; _dawarich_session=#{cookie}"}
    ])
  end

  test "unsupported formats and scalar coercions replay without effects", ctx do
    rejected =
      request(
        ctx,
        :post,
        "/tracks/42/segments/43",
        body(ctx, "_method=patch&track_segment[transportation_mode]=walking"),
        [
          {"content-type", "application/json"}
        ]
      )

    assert rejected.halted

    replay(
      ctx,
      :post,
      "/tracks/42/segments/43",
      ~s({"track_segment":{"transportation_mode":"walking"}}),
      [
        {"content-type", "application/json"}
      ]
    )

    raw = body(ctx, "_method=patch&track_segment[transportation_mode]=walking")
    replay(ctx, :post, "/tracks/42/segments/43", raw, [{"content-type", "application/json"}])
    replay(ctx, :post, "/tracks/42/segments/43", raw, [{"accept", "application/json"}])
    replay(ctx, :post, "/tracks/42/segments/43", raw, [{"x-requested-with", "XMLHttpRequest"}])

    for {method, path, suffix} <- [
          {:delete, "/points/bulk_destroy", "point_ids[bad]=42"},
          {:delete, "/points/bulk_destroy?start_at=1&start_at=2", "point_ids[]=42"}
        ] do
      replay(ctx, method, path, body(ctx, suffix))
    end

    for {accept, expected} <- [
          {"text/vnd.turbo-stream.html", :turbo_stream},
          {"text/vnd.turbo-stream.html, text/html, application/xhtml+xml", :turbo_stream},
          {"text/html, text/vnd.turbo-stream.html", :html},
          {"text/html;q=0.5, text/vnd.turbo-stream.html;q=1", :turbo_stream},
          {"text/vnd.turbo-stream.html;q=0.5, text/html;q=1", :html},
          {"*/*", :turbo_stream}
        ] do
      conn =
        request(ctx, :patch, "/tracks/42/segments/43", body(ctx, "reset=true"), [
          {"accept", accept}
        ])

      refute conn.halted
      assert conn.assigns.map_write_format == expected
    end
  end

  test "captured points list browser POST admits fixed routing query and document Accept", ctx do
    accept =
      "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"

    path =
      "/points/bulk_destroy?action=index&controller=points&start_at=2020-07-04T00%3A00%3A00Z&end_at=2020-07-04T23%3A59%3A59Z&import_id=17&order_by=asc"

    suffix = "_method=delete&point_ids[]=42"
    raw = body(ctx, suffix)
    conn = request(ctx, :post, path, raw, [{"accept", accept}])
    refute conn.halted
    assert conn.assigns.map_write_action == :point_destroy
    assert conn.assigns.map_write_method == "DELETE"
    assert conn.assigns.map_write_format == :html
    assert conn.assigns.api_params["point_ids"] == ["42"]
    assert conn.private.dawarich_raw_body == raw
    replay(ctx, :post, path, "authenticity_token=invalid&" <> suffix, [{"accept", accept}])

    for query <- [
          "controller=tags&action=index",
          "controller=points&action=destroy",
          "controller=points&controller=points&action=index",
          "controller[bad]=points&action=index"
        ] do
      replay(ctx, :post, "/points/bulk_destroy?" <> query, raw, [{"accept", accept}])
    end

    replay(ctx, :post, path, raw, [{"accept", "application/json"}])
    assert snapshot() == [[0, 0, 0]]
    assert commands() == []
  end

  test "scalar point filters honor captured Rails query precedence", ctx do
    raw = body(ctx, "point_ids[]=42&start_at=body&end_at=end&order_by=asc&import_id=17")
    conn = request(ctx, :delete, "/points/bulk_destroy?start_at=query&order_by=desc", raw)
    refute conn.halted
    assert conn.assigns.api_query == %{"start_at" => "query", "order_by" => "desc"}
    assert conn.assigns.api_params["start_at"] == "query"
    assert conn.assigns.api_params["order_by"] == "desc"
    assert conn.assigns.api_params["end_at"] == "end"
    assert conn.private.dawarich_raw_body == raw
    assert snapshot() == [[0, 0, 0]]
    assert commands() == []
  end
end
