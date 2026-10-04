defmodule DawarichWeb.TagActionsTest do
  use Dawarich.IngestCase, async: false

  import Plug.Conn
  import Plug.Test
  import Dawarich.Test.RailsFormRequests, only: [upstream!: 0, forwarded: 2, rails_session: 1]
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{RailsAuth, RailsCsrf, MapWriteRequest, TagActions, Translate}

  setup do
    user =
      RailsUser.insert!(%{id: 9196, email: "a6s4-response@example.invalid", status: 0, plan: 0})

    session = RailsUser.session(user.id)
    upstream = upstream!()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})
    %{user: user, session: session, upstream: upstream}
  end

  defp request(ctx, method, path, suffix) do
    raw =
      "authenticity_token=" <>
        URI.encode_www_form(RailsCsrf.masked_token(ctx.session)) <> "&" <> suffix

    {request_raw(ctx, method, path, raw), raw}
  end

  defp request_raw(ctx, method, path, raw) do
    method
    |> conn(path, raw)
    |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
    |> put_req_header("accept", "text/html")
    |> RailsAuth.call([])
    |> MapWriteRequest.call([])
    |> assign(:now, ~U[2026-10-03 10:00:00.000000Z])
    |> TagActions.call(if(path == "/tags", do: :create, else: :member))
  end

  defp values(html, selector, attribute),
    do:
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query(selector)
      |> LazyHTML.attribute(attribute)

  test "saves 302 deletion 303 with exact translated Rails flash", ctx do
    for locale <- ["en", "de"] do
      Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [ctx.user.id, %{"locale" => locale}])

      {created, _} = request(ctx, :post, "/tags", "tag[name]=Created-#{locale}")
      assert created.status == 302
      assert get_resp_header(created, "location") == ["http://www.example.com/tags"]

      assert rails_session(created)["flash"] == %{
               "discard" => [],
               "flashes" => %{
                 "notice" =>
                   Translate.t(locale, "controllers.tags.tag_was_successfully_created", %{})
               }
             }

      [[id]] = Repo.query!("SELECT id FROM tags WHERE name=$1", ["Created-#{locale}"]).rows
      {updated, _} = request(ctx, :put, "/tags/#{id}", "tag[name]=Updated-#{locale}")
      assert updated.status == 302

      assert rails_session(updated)["flash"]["flashes"]["notice"] ==
               Translate.t(locale, "controllers.tags.tag_was_successfully_updated", %{})

      {deleted, _} = request(ctx, :post, "/tags/#{id}", "_method=delete")
      assert deleted.status == 303

      assert rails_session(deleted)["flash"]["flashes"]["notice"] ==
               Translate.t(locale, "controllers.tags.tag_was_successfully_deleted", %{})
    end

    assert Repo.query!("SELECT count(*) FROM tags").rows == [[0]]
    assert commands() == []
  end

  test "invalid new edit 422 retain submitted fields errors wrappers", ctx do
    for {path, suffix} <- [
          {"/tags",
           "tag[name]=&tag[icon]=abcdefghijk&tag[color]=oops&tag[privacy_radius_meters]=-1"},
          {"/tags/91961",
           "tag[name]=&tag[icon]=abcdefghijk&tag[color]=oops&tag[privacy_radius_meters]=-1"}
        ] do
      if path != "/tags",
        do:
          Repo.insert_all("tags", [
            %{
              id: 91961,
              user_id: ctx.user.id,
              name: "Original",
              demo: true,
              created_at: ~N[2026-10-02 10:00:00],
              updated_at: ~N[2026-10-02 10:00:00]
            }
          ])

      before = Repo.query!("SELECT * FROM tags ORDER BY id").rows
      {response, _} = request(ctx, if(path == "/tags", do: :post, else: :patch), path, suffix)
      assert response.status == 422
      assert get_resp_header(response, "content-type") == ["text/html; charset=utf-8"]
      assert response.resp_body =~ "<!DOCTYPE html>"
      assert response.resp_body =~ "5 errors prohibited this tag from being saved:"
      assert values(response.resp_body, ".field_with_errors input#tag_name", "value") == [""]

      for field <- ~w(name icon color privacy_radius_meters),
          do:
            assert(
              values(response.resp_body, ".field_with_errors label[for='tag_#{field}']", "class") ==
                ["label"]
            )

      assert values(response.resp_body, "input#tag_icon", "value") == ["abcdefghijk"]
      assert values(response.resp_body, "input#tag_color", "value") == ["oops"]
      assert values(response.resp_body, "input#tag_privacy_radius_meters", "value") == ["-1"]

      errors =
        response.resp_body
        |> LazyHTML.from_document()
        |> LazyHTML.query("form .alert-error li")
        |> Enum.map(&LazyHTML.text/1)

      oracle =
        Path.expand("../fixtures/map_writes/tags/multi_error.json", __DIR__)
        |> File.read!()
        |> Jason.decode!()

      assert errors == Enum.map(oracle["validation"]["errors"], & &1["message"])
      assert Repo.query!("SELECT * FROM tags ORDER BY id").rows == before
    end

    {escaped, _} = request(ctx, :post, "/tags", "tag[name]=%3Cscript%3E%26&tag[color]=bad")
    assert escaped.status == 422
    assert values(escaped.resp_body, "input#tag_name", "value") == ["<script>&"]
    refute escaped.resp_body =~ "value=\"<script>"
  end

  test "invalid document handles prior flash cookie as Rails does", ctx do
    flash = %{"discard" => [], "flashes" => %{"notice" => "Synthetic prior notice"}}
    ctx = %{ctx | session: Map.put(ctx.session, "flash", flash)}
    {response, _} = request(ctx, :post, "/tags", "tag[name]=")
    assert response.status == 422
    assert response.resp_body =~ "Synthetic prior notice"
    assert Map.has_key?(response.resp_cookies, "_dawarich_session")
    returned = rails_session(response)
    refute Map.has_key?(returned, "flash")
    assert returned["_csrf_token"] == ctx.session["_csrf_token"]
    assert returned["warden.user.user.key"] == ctx.session["warden.user.user.key"]
    assert Repo.query!("SELECT count(*) FROM tags").rows == [[0]]
  end

  test "unsupported render race rolls back then replays once raw", ctx do
    ctx = %{ctx | session: Map.put(ctx.session, "padding", String.duplicate("x", 4000))}

    raw =
      "authenticity_token=" <>
        URI.encode_www_form(RailsCsrf.masked_token(ctx.session)) <> "&tag[name]=Render-race"

    before = Repo.query!("SELECT * FROM tags ORDER BY id").rows
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, ctx.upstream.port})

    {{line, forwarded_body}, response} =
      forwarded(ctx.upstream, fn -> request_raw(ctx, :post, "/tags", raw) end)

    assert response.status == 204
    assert line == "POST /tags HTTP/1.1"
    assert byte_size(forwarded_body) == byte_size(raw)
    assert :crypto.hash(:sha256, forwarded_body) == :crypto.hash(:sha256, raw)
    assert Repo.query!("SELECT * FROM tags ORDER BY id").rows == before
    assert commands() == []
  end
end
