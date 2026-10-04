defmodule DawarichWeb.Api.AccountEndpointTest do
  use Dawarich.ApiEndpointCase
  use Dawarich.JobsCase, async: false
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

  @tag :account_manager
  test "exist preserves missing-id status and ignores bearer auth", ctx do
    previous = System.get_env("SUBSCRIPTION_WEBHOOK_SECRET")
    System.put_env("SUBSCRIPTION_WEBHOOK_SECRET", "a4rest-manager-synthetic")

    on_exit(fn ->
      if previous,
        do: System.put_env("SUBSCRIPTION_WEBHOOK_SECRET", previous),
        else: System.delete_env("SUBSCRIPTION_WEBHOOK_SECRET")
    end)

    for body <- ["{}", ~s({"ids":null})] do
      client =
        request(
          ctx.port,
          "/api/v1/users/exist",
          [
            {"Accept", "application/json"},
            {"Content-Type", "application/json"},
            {"Content-Length", Integer.to_string(byte_size(body))},
            {"Authorization", "Bearer unknown-synthetic"},
            {"X-Webhook-Secret", "a4rest-manager-synthetic"}
          ],
          "POST"
        )

      send_raw(client, body)
      assert {422, _, ~s({"error":"ids is required"})} = read_response(client)
    end

    no_upstream!(ctx.upstream)
  end

  @tag :account_delete_body
  test "account deletion preserves DELETE body on Rails hand-back", ctx do
    for body <- [
          ~s({"password":"synthetic-correct"}),
          ~s({"password":"synthetic-wrong"}),
          ~s({"confirm_email":" SYNTHETIC@EXAMPLE.INVALID "}),
          "{}"
        ] do
      replay!(ctx, "DELETE", "/api/v1/users/me", body)
    end
  end

  @tag :account_delete_state
  test "account deletion hand-back leaves native tombstone and effects untouched", ctx do
    for {status, provider, body} <- [
          {1, nil, ~s({"password":"synthetic-correct"})},
          {3, nil, ~s({"password":"synthetic-correct"})},
          {1, "openid_connect", ~s({"confirm_email":"synthetic@example.invalid"})},
          {1, nil, "{}"}
        ] do
      Repo.query!("UPDATE users SET status=$1,provider=$2 WHERE id=$3", [
        status,
        provider,
        ctx.owner
      ])

      [[seed]] =
        Repo.query!("SELECT row_to_json(u)::text FROM users u WHERE id=$1", [ctx.owner]).rows

      rows("DELETE FROM users WHERE id=$1", [ctx.owner])
      Dawarich.Test.ApiGolden.insert!("users", Jason.decode!(seed), ScratchRepo)

      if body == "{}" do
        other = user!()

        [[other_seed]] =
          Repo.query!("SELECT row_to_json(u)::text FROM users u WHERE id=$1", [other]).rows

        Dawarich.Test.ApiGolden.insert!("users", Jason.decode!(other_seed), ScratchRepo)

        rows(
          "INSERT INTO families(id,creator_id,name,created_at,updated_at) VALUES(954101,$1,'Synthetic family',now(),now())",
          [ctx.owner]
        )

        rows(
          "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES(954101,$1,0,now(),now()),(954101,$2,1,now(),now())",
          [ctx.owner, other]
        )
      end

      before = rows("SELECT deleted_at FROM users WHERE id=$1", [ctx.owner])
      effects = rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id")
      replay!(ctx, "DELETE", "/api/v1/users/me", body)
      assert Repo.query!("SELECT deleted_at FROM users WHERE id=$1", [ctx.owner]).rows == [[nil]]
      assert rows("SELECT deleted_at FROM users WHERE id=$1", [ctx.owner]) == before
      assert rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id") == effects
    end
  end

  defp replay!(ctx, method, target, body) do
    client = submit(ctx, method, target, body, [])
    puma = accept(ctx.upstream)
    {head, rest} = read_head(puma)
    assert request_line(head) == "#{method} #{target} HTTP/1.1"
    assert read_at_least(puma, rest, byte_size(body)) == body
    reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nrails")
    assert {200, _, "rails"} = read_response(client)
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
