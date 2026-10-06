defmodule DawarichWeb.Api.SharedEndpointTest do
  use Dawarich.ApiEndpointCase
  use Dawarich.JobsCase, async: false

  alias Dawarich.{RailsCookies, RailsSecret}
  alias DawarichWeb.SharedLinkCookie

  @moduletag :capture_log
  @id "a4951000-0000-4000-8000-000000000001"
  @actions ~w(trip points route photos photos/synthetic/thumbnail)
  @headers [{"Accept", "application/json"}]

  setup do
    user = user!(%{status: 3, api_key: "shared-pending", settings: %{}})
    stamp = NaiveDateTime.utc_now()

    Repo.insert_all("shared_links", [
      %{
        id: Ecto.UUID.dump!(@id),
        user_id: user,
        resource_type: 1,
        resource_id: nil,
        name: "Synthetic shared link",
        settings: %{},
        created_at: stamp,
        updated_at: stamp
      }
    ])

    %{user: user}
  end

  test "shared API rejects expired revoked and absent links before reads", ctx do
    for {column, value} <- [
          {"revoked_at", NaiveDateTime.utc_now()},
          {"expires_at", ~N[2020-01-01 00:00:00]}
        ] do
      Repo.query!("UPDATE shared_links SET #{column} = $1 WHERE id = $2::text::uuid", [value, @id])

      for action <- @actions do
        assert {404, _, ~s({"error":"not_found"})} = response(ctx, action)
      end

      Repo.query!("UPDATE shared_links SET #{column} = NULL WHERE id = $1::text::uuid", [@id])
    end

    Repo.query!("DELETE FROM shared_links WHERE id = $1::text::uuid", [@id])

    for action <- @actions,
        do: assert({404, _, ~s({"error":"not_found"})} = response(ctx, action))

    assert commands() == []
    no_upstream!(ctx.upstream)
  end

  test "rotated phrase invalidates the old Rails unlock cookie", ctx do
    phrase!("synthetic-old")
    old = cookie("synthetic-old")
    assert {200, _, "[]"} = response(ctx, "route", old)
    phrase!("synthetic-new")

    for action <- @actions do
      assert {401, _, ~s({"error":"unauthorized"})} = response(ctx, action, old)
    end

    assert {200, _, "[]"} = response(ctx, "route", cookie("synthetic-new"))
    assert {401, _, _} = response(ctx, "route")
    no_upstream!(ctx.upstream)
  end

  test "shared API is public without account payment or Dawarich headers", ctx do
    for headers <- [
          [],
          [{"Authorization", "Bearer shared-pending"}],
          [{"Cookie", "_dawarich_session=invalid"}]
        ] do
      assert {200, response_headers, "[]"} = response(ctx, "route", headers)

      refute Enum.any?(response_headers, fn {name, _} ->
               String.starts_with?(name, "x-dawarich") or name == "set-cookie"
             end)
    end

    assert Repo.query!(
             "SELECT view_count, last_accessed_at FROM shared_links WHERE id = $1::text::uuid",
             [@id]
           ).rows == [[0, nil]]

    for action <- @actions do
      path = "/api/v1/shared/#{@id}/#{action}"
      info = Phoenix.Router.route_info(DawarichWeb.Router, "GET", path, "localhost")
      assert info.slice == :api_shared

      for {method, slices, hosted} <- [
            {"GET", "api_shared", "true"},
            {"HEAD", "", "true"},
            {"GET", "", "false"}
          ] do
        System.put_env("DAWARICH_RAILS_SLICES", slices)
        System.put_env("SELF_HOSTED", hosted)
        client = request(ctx.port, path, @headers, method)

        assert puma(ctx.upstream, if(method == "HEAD", do: "", else: "rails")) ==
                 "#{method} #{path} HTTP/1.1"

        assert {200, _, _} = read_response(client, method: method)
      end
    end
  end

  test "shared API preserves default locale caching and conditional responses", ctx do
    assert {200, headers, "[]"} =
             response(ctx, "route?locale=de", [
               {"Accept-Language", "de"},
               {"X-Request-Id", "synthetic@id"}
             ])

    assert {"cache-control", "max-age=30, public"} in headers
    assert {"vary", "Accept"} in headers
    assert {"x-request-id", "synthetic@id"} in headers
    {_, etag} = List.keyfind(headers, "etag", 0)
    assert {304, conditional, ""} = response(ctx, "route", [{"If-None-Match", etag}])
    refute List.keymember?(conditional, "content-type", 0)
    phrase!("synthetic-private")
    assert {200, private, "[]"} = response(ctx, "route", cookie("synthetic-private"))
    assert {"cache-control", "max-age=0, private, must-revalidate"} in private
    assert {401, _, ~s({"error":"unauthorized"})} = response(ctx, "trip?locale=de")
    no_upstream!(ctx.upstream)
  end

  defp response(ctx, action, headers \\ []),
    do:
      ctx.port
      |> request("/api/v1/shared/#{@id}/#{action}", @headers ++ headers)
      |> read_response()

  @tag :shared_viewer_zone
  test "signed browser shared metadata uses viewer zone without payment gate", ctx do
    password = String.duplicate("synthetic-account-salt-", 3)

    Repo.query!("UPDATE users SET encrypted_password=$1,settings=$2 WHERE id=$3", [
      password,
      %{"timezone" => "Asia/Tokyo"},
      ctx.user
    ])

    Repo.query!(
      "INSERT INTO trips(id,user_id,name,started_at,ended_at,created_at,updated_at) VALUES(951101,$1,'Synthetic trip','2026-03-29 00:00:00','2026-03-29 01:00:00',now(),now())",
      [ctx.user]
    )

    Repo.query!(
      "UPDATE shared_links SET resource_type=0,resource_id=951101 WHERE id=$1::text::uuid",
      [@id]
    )

    session = %{"warden.user.user.key" => [[ctx.user], String.slice(password, 0, 29)]}

    value =
      RailsCookies.encrypt(
        session,
        "_dawarich_session",
        RailsSecret.fetch(),
        DateTime.add(DateTime.utc_now(), 3600)
      )

    assert {200, headers, body} =
             response(ctx, "trip", [{"Cookie", "_dawarich_session=#{value}"}])

    assert Jason.decode!(body)["started_at"] == "2026-03-29T09:00:00.000+09:00"
    assert values(headers, "x-dawarich-response") == []
    assert values(headers, "set-cookie") == []
    assert rows("SELECT kind,payload FROM phoenix.rails_commands") == []
    no_upstream!(ctx.upstream)
  end

  @tag :shared_remembered_zone
  test "remembered shared requests preserve cookie on Rails hand-back", ctx do
    before = Repo.query!("SELECT row_to_json(s)::text FROM shared_links s").rows
    cookie = "remember_user_token=synthetic-original-signed-cookie"
    target = "/api/v1/shared/#{@id}/route"
    client = request(ctx.port, target, @headers ++ [{"Cookie", cookie}])
    puma = Dawarich.Test.ApiGolden.rails_connection(client, ctx.upstream)
    {head, _rest} = read_head(puma)
    assert request_line(head) == "GET #{target} HTTP/1.1"
    assert header(head, "cookie") == [cookie]
    reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nrails")
    assert {200, _, "rails"} = read_response(client)
    assert Repo.query!("SELECT row_to_json(s)::text FROM shared_links s").rows == before
    assert rows("SELECT kind,payload FROM phoenix.rails_commands") == []
  end

  defp phrase!(phrase),
    do:
      Repo.query!("UPDATE shared_links SET magic_phrase = $1 WHERE id = $2::text::uuid", [
        phrase,
        @id
      ])

  defp cookie(phrase) do
    name = "shared_link_#{@id}"

    value =
      RailsCookies.encrypt(
        SharedLinkCookie.unlock_token(@id, phrase),
        name,
        RailsSecret.fetch(),
        DateTime.add(DateTime.utc_now(), 3600)
      )

    [{"Cookie", "#{name}=#{value}"}]
  end
end
