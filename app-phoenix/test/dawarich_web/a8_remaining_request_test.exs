defmodule DawarichWeb.A8RemainingRequestTest do
  use Dawarich.IngestCase, async: false

  import Plug.Conn
  import Plug.Test
  import Dawarich.Test.RailsFormRequests, only: [upstream!: 0, forwarded: 2]

  alias Dawarich.Test.RailsUser
  alias Dawarich.{RailsCookies, RailsSecret}
  alias DawarichWeb.{A8FormDecode, A8Gate, A8Request, RailsAuth, RailsCsrf, Strangler}

  setup do
    now = DateTime.utc_now()

    actor =
      RailsUser.insert!(%{
        id: 896_900,
        email: "a8-rest-form@example.invalid",
        remember_created_at: now |> DateTime.add(-60) |> DateTime.to_naive()
      })

    session = RailsUser.session(actor.id)

    remember =
      RailsCookies.sign(
        [[actor.id], String.slice(actor.encrypted_password, 0, 29), DateTime.to_iso8601(now)],
        "remember_user_token",
        RailsSecret.fetch(),
        DateTime.add(now, 3600)
      )

    upstream = upstream!()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})

    %{
      session: session,
      token: RailsCsrf.masked_token(session),
      upstream: upstream,
      remember: remember
    }
  end

  defp request(ctx, method, path, body, headers \\ []) do
    method
    |> conn(path, body)
    |> put_req_header(
      "cookie",
      "_dawarich_session=#{RailsUser.cookie(ctx.session)}; remember_user_token=#{ctx.remember}"
    )
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("accept", "text/vnd.turbo-stream.html")
    |> put_req_header("origin", "http://www.example.com")
    |> then(fn conn ->
      Enum.reduce(headers, conn, fn {k, v}, conn -> put_req_header(conn, k, v) end)
    end)
    |> RailsAuth.call([])
    |> A8Request.call([])
  end

  defp snapshot do
    Repo.query!("""
    SELECT (SELECT count(*) FROM trips), (SELECT count(*) FROM notes),
      (SELECT count(*) FROM places), (SELECT count(*) FROM job_outbox),
      (SELECT count(*) FROM phoenix.rails_commands)
    """).rows
  end

  defp replay(ctx, method, path, body, headers \\ []) do
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, ctx.upstream.port})
    before = snapshot()

    {{line, received}, conn} =
      forwarded(ctx.upstream, fn ->
        conn = request(ctx, method, path, body, headers)
        assert conn.halted, "#{method} #{path}: expected Rails hand-back"
        conn
      end)

    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})

    assert conn.status == 204
    assert conn.halted
    assert line == "#{method |> Atom.to_string() |> String.upcase()} #{path} HTTP/1.1"
    assert received == body
    assert snapshot() == before

    if not Map.has_key?(ctx.session, "warden.user.user.key"),
      do: assert(conn.assigns.current_user.id == 896_900)
  end

  test "remaining forms preserve raw hand-back and validated overrides", ctx do
    token = "authenticity_token=" <> URI.encode_www_form(ctx.token)

    trip =
      "trip[name]=Auwald&trip[started_at]=2026-10-03T12%3A00&trip[ended_at]=2026-10-04T12%3A00"

    note = "note[date]=2026-10-03&note[body]=%0AAuwald"
    place = "place[name]=Leipzig&place[latitude]=51.34&place[longitude]=12.37"
    before = snapshot()

    for {method, path, raw, action, effective} <- [
          {:post, "/trips", trip, :trip_create, "POST"},
          {:patch, "/trips/42", trip, :trip_update, "PATCH"},
          {:put, "/trips/42", trip, :trip_update, "PUT"},
          {:post, "/trips/42", "_method=patch&" <> trip, :trip_update, "PATCH"},
          {:post, "/trips/42", "_method=put&" <> trip, :trip_update, "PUT"},
          {:post, "/trips/42", "_method=delete", :trip_destroy, "DELETE"},
          {:delete, "/trips/42", "", :trip_destroy, "DELETE"},
          {:post, "/trips/42/recalculate", "", :trip_recalculate, "POST"},
          {:post, "/trips/42/export?file_format=gpx", "", :trip_export, "POST"},
          {:post, "/trips/42/export", "file_format=json", :trip_export, "POST"},
          {:post, "/trips/42/notes", note, :note_create, "POST"},
          {:patch, "/trips/42/notes/7", note, :note_update, "PATCH"},
          {:put, "/trips/42/notes/7", note, :note_update, "PUT"},
          {:post, "/trips/42/notes/7", "_method=put&" <> note, :note_update, "PUT"},
          {:post, "/trips/42/notes/7", "_method=delete", :note_destroy, "DELETE"},
          {:delete, "/trips/42/notes/7", "", :note_destroy, "DELETE"},
          {:post, "/places", place <> "&place[tag_ids][]=&place[tag_ids][]=1&place[tag_ids][]=2",
           :place_create, "POST"},
          {:patch, "/places/42", place, :place_update, "PATCH"},
          {:put, "/places/42", place, :place_update, "PUT"},
          {:post, "/places/42", "_method=put&" <> place, :place_update, "PUT"},
          {:delete, "/places/42?page=2", "", :place_destroy, "DELETE"},
          {:post, "/places/42?page=2", "_method=delete", :place_destroy, "DELETE"}
        ] do
      body = token <> "&" <> raw
      conn = request(ctx, method, path, body)
      refute conn.halted, "#{method} #{path}"
      assert conn.assigns.a8_action == action
      assert conn.assigns.a8_method == effective
      refute Map.has_key?(conn.assigns.api_params, "_method")
      assert conn.private.dawarich_raw_body == body

      if action == :place_create,
        do: assert(conn.assigns.api_params["place"]["tag_ids"] == ["", "1", "2"])

      if String.contains?(path, "?"), do: assert(A8Gate.actions?(conn, %{}))
    end

    assert snapshot() == before

    for {path, raw} <- [
          {"/trips", trip <> "&trip[name]=duplicate"},
          {"/trips", "trip[name]=one&trip[name][]=two"},
          {"/trips", "trip=one&trip[name]=two"},
          {"/trips", "trip[name]=bad%Q1"},
          {"/trips", "trip[name]=%FF"},
          {"/trips", "trip[name]"},
          {"/trips", trip <> "&place[tag_ids][]=1&place[tag_ids][]=2"},
          {"/places", place <> "&place[tag_ids]=1&place[tag_ids][]=2"},
          {"/places", place <> "&place[name]=duplicate"},
          {"/trips/42/notes", note <> "&note[body]=duplicate"},
          {"/trips/42/notes", "note[body][text]=nested"},
          {"/trips/42/export?file_format=gpx&file_format=json", ""},
          {"/trips/42/export?file_format=gpx", "file_format=json"},
          {"/trips/42/export?file_format[]=gpx", ""},
          {"/trips/42/export?file_format=%Q1", ""},
          {"/places/42?page=2&page=3", "_method=delete"},
          {"/places/42?page=2", "_method=delete&page=3"},
          {"/places/42?page[]=2", "_method=delete"},
          {"/places/42?page=2", "_method=patch&" <> place},
          {"/trips?file_format=gpx", trip}
        ] do
      replay(ctx, :post, path, token <> "&" <> raw)
    end

    for key <- ~w(locale client aff via),
        {path, raw} <- [{"/trips", trip}, {"/places", place}, {"/trips/42/notes", note}] do
      replay(ctx, :post, path, token <> "&" <> raw <> "&#{key}=en")
      replay(ctx, :post, path <> "?#{key}=en", token <> "&" <> raw)
    end

    for {path, raw} <- [{"/trips", trip}, {"/places", place}, {"/trips/42/notes", note}] do
      body = token <> "&" <> raw
      replay(ctx, :post, path, body, [{"origin", "http://foreign.test"}])
      replay(ctx, :post, path, "authenticity_token=invalid&" <> raw)
      replay(ctx, :post, path, body, [{"x-dawarich-client", "ios"}])
      replay(ctx, :post, path, body, [{"x-http-method-override", "PATCH"}])
      replay(ctx, :post, path, "{}", [{"content-type", "application/json"}])
      replay(%{ctx | session: %{}}, :post, path, body)
      remembered = %{ctx | session: Map.delete(ctx.session, "warden.user.user.key")}
      replay(remembered, :post, path, body)
    end

    for {method, path, raw} <- [
          {:post, "/trips", "_method=delete&" <> trip},
          {:post, "/trips/42", "_method=get&" <> trip},
          {:patch, "/trips/42", "_method=delete&" <> trip},
          {:post, "/trips/42/recalculate", "_method=patch"},
          {:post, "/trips/42/notes", "_method=delete&" <> note},
          {:post, "/places", "_method=patch&" <> place},
          {:post, "/places/42", place},
          {:post, "/trips/not-number/notes", note},
          {:post, "/trips/42/notes/1234567890123456789", "_method=delete"},
          {:post, "/places/nearby", place}
        ] do
      replay(ctx, method, path, token <> "&" <> raw)
    end

    for {path, fields} <- [
          {"/trips", [{"trip[name]", "Auwald"}]},
          {"/trips/42/notes", [{"note[body]", "\nAuwald"}]},
          {"/places",
           [{"place[name]", "Leipzig"}, {"place[tag_ids][]", "1"}, {"place[tag_ids][]", "2"}]}
        ] do
      body =
        Enum.map_join([{"authenticity_token", ctx.token} | fields], "", fn {key, value} ->
          "--a8rest\r\nContent-Disposition: form-data; name=\"#{key}\"\r\n\r\n#{value}\r\n"
        end) <> "--a8rest--\r\n"

      headers = [{"content-type", "multipart/form-data; boundary=a8rest"}]
      conn = request(ctx, :post, path, body, headers)
      refute conn.halted
      assert conn.private.dawarich_raw_body == body

      for extra <- [{"content-length", "2097153"}, {"transfer-encoding", "chunked"}] do
        blocked =
          conn(:post, path, body)
          |> put_req_header("content-type", "multipart/form-data; boundary=a8rest")
          |> put_req_header("content-length", Integer.to_string(byte_size(body)))
          |> put_req_header(elem(extra, 0), elem(extra, 1))

        refute A8Gate.actions?(blocked, %{})
        assert {:replay, untouched} = A8FormDecode.params(blocked, ["place[tag_ids][]"])
        assert {:ok, ^body, _} = read_body(untouched)
      end

      uploaded = String.replace(body, "name=\"", "filename=\"file\"; name=\"")
      replay(ctx, :post, path, uploaded, headers)
    end

    for route <- [
          "/trips/:id/edit",
          "/trips/:id/recalculate",
          "/trips/:id/export",
          "/trips/:trip_id/notes",
          "/trips/:trip_id/notes/:id"
        ] do
      assert Strangler.rails_constraints?(%{
               route: route,
               path_params: %{"id" => "42", "trip_id" => "43"}
             })

      refute Strangler.rails_constraints?(%{
               route: route,
               path_params: %{"id" => "bad", "trip_id" => "bad"}
             })
    end

    assert snapshot() == before
  end
end
