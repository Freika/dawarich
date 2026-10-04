defmodule DawarichWeb.Api.AccountEndpointTest do
  use Dawarich.ApiEndpointCase
  @moduletag api_public_only: true
  @moduletag :capture_log
  @key "a4rest-account-inactive-synthetic"

  setup do
    owner = user!(%{status: 0, api_key: @key, settings: %{"timezone" => "UTC"}})
    %{owner: owner}
  end

  @tag :account_payment
  test "me accepts inactive user but rejects pending payment", ctx do
    assert {200, headers, _} = call(ctx, "GET", "/api/v1/users/me")
    assert values(headers, "x-dawarich-response") == ["Hey, I'm alive and authenticated!"]
    Repo.query!("UPDATE users SET status=3 WHERE id=$1", [ctx.owner])
    assert {402, _, body} = call(ctx, "GET", "/api/v1/users/me")
    assert Jason.decode!(body)["error"] == "payment_required"
    no_upstream!(ctx.upstream)
  end

  @tag :account_subscription
  test "me never issues credentials or exposes Cloud subscription", ctx do
    before = Repo.query!("SELECT row_to_json(u)::text FROM users u WHERE id=$1", [ctx.owner]).rows
    assert {200, headers, raw} = call(ctx, "GET", "/api/v1/users/me")
    body = Jason.decode!(raw)
    assert Enum.sort(Map.keys(body)) == ["features", "user"]

    assert Enum.sort(Map.keys(body["user"])) == [
             "created_at",
             "email",
             "id",
             "settings",
             "theme",
             "updated_at"
           ]

    assert values(headers, "set-cookie") == []

    assert Repo.query!("SELECT row_to_json(u)::text FROM users u WHERE id=$1", [ctx.owner]).rows ==
             before

    etag = hd(values(headers, "etag"))
    assert {304, _, ""} = call(ctx, "GET", "/api/v1/users/me", "", [{"If-None-Match", etag}])
    no_upstream!(ctx.upstream)
  end

  defp call(ctx, method, target, body \\ "", headers \\ []) do
    ctx |> submit(method, target, body, headers) |> read_response()
  end

  defp submit(ctx, method, target, body, headers) do
    client = connect(ctx.port)

    send_raw(client, [
      "#{method} #{target} HTTP/1.1\r\nHost: localhost\r\nAccept: application/json\r\nAuthorization: Bearer #{@key}\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(body)}\r\n",
      Enum.map(headers, fn {name, value} -> "#{name}: #{value}\r\n" end),
      "\r\n",
      body
    ])

    client
  end
end
