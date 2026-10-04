defmodule DawarichWeb.A10cOwnershipTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log
  import Dawarich.Test.RawHTTP
  alias Dawarich.{Repo, Redis}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    for spec <- Redis.child_specs() ++ Redis.cache_child_specs(), do: start_supervised!(spec)
    upstream = listen()
    saved = Map.new(~w(rails_upstream rails_routes)a, &{&1, Application.fetch_env(:dawarich, &1)})
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    Application.put_env(:dawarich, :rails_routes, [])

    on_exit(fn ->
      :gen_tcp.close(upstream.listen)

      for {key, value} <- saved do
        case value do
          {:ok, configured} -> Application.put_env(:dawarich, key, configured)
          :error -> Application.delete_env(:dawarich, key)
        end
      end
    end)

    for id <- [44001, 44002],
        do:
          RailsUser.insert!(%{
            id: id,
            email: "a10c-ownership-#{id}@example.invalid",
            settings: %{"locale" => "en", "timezone" => "Europe/Berlin"}
          })

    rows(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES(44001,'exploration','{}',now(),now())"
    )

    rows(
      "INSERT INTO achievement_unlock_events(id,user_id,kind,key,created_at,updated_at) VALUES(42001,44001,'geography','FR',now(),now())"
    )

    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(bandit)
    %{upstream: upstream, port: port}
  end

  test "owns supported achievement actions and rolls them back before any effect", ctx do
    {200, _, body} =
      exchange(ctx, "PATCH", "/achievements/country_de/toggle_sharing", ~s({"enabled":true}))

    assert Jason.decode!(body)["enabled"] == true

    assert [[true]] ==
             rows(
               "SELECT sharing_enabled FROM achievement_progresses WHERE user_id=44001 AND achievement_key='country_de'"
             )

    {200, _, body} = exchange(ctx, "POST", "/achievements/unlocks/next", "{}")
    deck = Jason.decode!(body)
    assert deck["id"] == 42001 and deck["remaining"] == 1

    assert {204, _, ""} =
             exchange(
               ctx,
               "POST",
               "/achievements/unlocks/42001/seen",
               Jason.encode!(%{claim_token: deck["token"]})
             )

    assert {204, _, ""} =
             exchange(ctx, "POST", "/achievements/unlocks/dismiss", ~s({"batch_end_id":42001}))

    form = URI.encode_query(%{"_method" => "patch", "enabled" => "false"})

    assert {302, _, ""} =
             exchange(ctx, "POST", "/achievements/country_de/toggle_sharing", form, form: true)

    assert [[false]] ==
             rows(
               "SELECT sharing_enabled FROM achievement_progresses WHERE user_id=44001 AND achievement_key='country_de'"
             )

    rows(
      "INSERT INTO achievement_unlock_events(id,user_id,kind,key,created_at,updated_at) VALUES(42002,44001,'geography','DE',now(),now())"
    )

    for {method, path, raw, opts} <- [
          {"PATCH", "/achievements/country_de/toggle_sharing", ~s({"enabled":true}), []},
          {"POST", "/achievements/country_de/toggle_sharing", form, [form: true]},
          {"POST", "/achievements/unlocks/next", "{}", []},
          {"POST", "/achievements/unlocks/42001/seen", ~s({"claim_token":"synthetic"}), []},
          {"POST", "/achievements/unlocks/dismiss", ~s({"batch_end_id":42001}), []}
        ] do
      Application.put_env(:dawarich, :rails_routes, ["achievements"])
      before = snapshot()
      assert {203, _, "Rails"} = exchange(ctx, method, path, raw, opts ++ [proxy: true])
      assert snapshot() == before
      Application.put_env(:dawarich, :rails_routes, [])
    end

    for {raw, opts} <- [
          {~s({"enabled":false,"enabled":true}), []},
          {"{}", [token: "invalid"]},
          {~s({"enabled":{"nested":true}}), []},
          {"{}", [guest: true]}
        ] do
      before = snapshot()

      assert {203, _, "Rails"} =
               exchange(
                 ctx,
                 "PATCH",
                 "/achievements/country_de/toggle_sharing",
                 raw,
                 opts ++ [proxy: true]
               )

      assert snapshot() == before
    end
  end

  test "hands back unsupported persisted state before locale or session effects", ctx do
    uuid = "a10c0000-0000-4000-8000-000000044001"

    rows(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,sharing_enabled,sharing_uuid,created_at,updated_at) VALUES(44001,'country_de','{}',true,$1,now(),now())",
      [uuid]
    )

    for invalid <- [[], %{"earned" => []}, %{"earned" => %{"DE-BY" => "not-an-approved-date"}}] do
      rows(
        "UPDATE achievement_progresses SET state=$1 WHERE user_id=44001 AND achievement_key='exploration'",
        [invalid]
      )

      for {method, path, body, user} <- [
            {"POST", "/achievements/unlocks/next?locale=de", "{}", 44001},
            {"GET", "/shared/achievements/#{uuid}?locale=de", "", 44002}
          ] do
        before = snapshot()
        {203, headers, "Rails"} = exchange(ctx, method, path, body, proxy: true, user: user)
        assert values(headers, "set-cookie") == []
        assert snapshot() == before
      end
    end

    rows(
      "UPDATE achievement_progresses SET state='{}' WHERE user_id=44001 AND achievement_key='exploration'"
    )

    before = snapshot()

    {203, headers, "Rails"} =
      exchange(ctx, "GET", "/shared/achievements/#{uuid}?locale=de", "", proxy: true)

    assert values(headers, "set-cookie") == []
    assert snapshot() == before

    rows("UPDATE users SET settings='[]' WHERE id=44001")
    before = snapshot()

    assert {203, headers, "Rails"} =
             exchange(
               ctx,
               "PATCH",
               "/achievements/country_de/toggle_sharing?locale=de",
               ~s({"enabled":true}),
               proxy: true
             )

    assert values(headers, "set-cookie") == []
    assert snapshot() == before
  end

  test "independently rolls public cards back and retains all other A10 residues", ctx do
    uuid = "a10c0000-0000-4000-8000-000000044001"

    rows(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,sharing_enabled,sharing_uuid,created_at,updated_at) VALUES(44001,'country_de','{}',true,$1,now(),now())",
      [uuid]
    )

    path = "/shared/achievements/#{uuid}"
    {200, headers, body} = exchange(ctx, "GET", path, "", guest: true)
    assert body =~ "Germany Explorer" and not (body =~ "data-phx")
    assert values(headers, "x-frame-options") == []
    assert values(headers, "content-security-policy") == ["frame-ancestors *"]

    for key <- ~w(shared achievements) do
      Application.put_env(:dawarich, :rails_routes, [key])
      before = snapshot()
      assert {203, _, "Rails"} = exchange(ctx, "GET", path, "", proxy: true, guest: true)
      assert snapshot() == before
    end

    Application.put_env(:dawarich, :rails_routes, [])

    for {method, path, raw} <- [
          {"GET", path <> "/og.png", ""},
          {"HEAD", path <> "/og.png", ""},
          {"DELETE", "/settings/users/44001", ""},
          {"POST", "/settings/users/44001", "_method=delete"},
          {"GET", "/settings/users/export", ""},
          {"POST", "/settings/users/import", "payload=synthetic"},
          {"POST", "/settings/background_jobs", "job=synthetic"},
          {"POST", "/admin/settings/test_geocoding", ""},
          {"GET", "/sidekiq", ""},
          {"GET", "/admin/flipper", ""}
        ] do
      before = snapshot()
      assert {203, _, _} = exchange(ctx, method, path, raw, proxy: true, form: method == "POST")
      assert snapshot() == before
    end
  end

  defp exchange(ctx, method, target, raw, opts \\ []) do
    session = RailsUser.session(Keyword.get(opts, :user, 44001))
    path = URI.parse(target).path
    effective = if raw =~ "_method=patch", do: "PATCH", else: method

    token =
      Keyword.get_lazy(opts, :token, fn ->
        RailsCsrf.masked_form_token(session, path, effective)
      end)

    form = Keyword.get(opts, :form, false)
    raw = if form, do: raw <> "&" <> URI.encode_query(%{"authenticity_token" => token}), else: raw

    cookie =
      if opts[:guest], do: "", else: "Cookie: _dawarich_session=#{RailsUser.cookie(session)}\r\n"

    type = if form, do: "application/x-www-form-urlencoded", else: "application/json"

    headers =
      if method in ~w(GET HEAD DELETE),
        do: "Accept: text/html\r\n",
        else:
          "Accept: #{if form, do: "text/html", else: "application/json"}\r\nContent-Type: #{type}\r\n" <>
            if(form, do: "", else: "X-CSRF-Token: #{token}\r\n")

    client = connect(ctx.port)

    send_raw(
      client,
      "#{method} #{target} HTTP/1.1\r\nHost: www.example.com\r\n#{cookie}#{headers}Content-Length: #{byte_size(raw)}\r\n\r\n#{raw}"
    )

    if opts[:proxy] do
      upstream = accept(ctx.upstream)
      {head, rest} = read_head(upstream)
      length = header(head, "content-length") |> List.first("0") |> String.to_integer()
      received = read_at_least(upstream, rest, length) |> binary_part(0, length)

      reply(
        upstream,
        "HTTP/1.1 203 Non-Authoritative Information\r\nContent-Length: 5\r\n\r\nRails"
      )

      :gen_tcp.close(upstream)
      assert request_line(head) == "#{method} #{target} HTTP/1.1"
      assert received == raw
    else
      assert {:error, :timeout} == :gen_tcp.accept(ctx.upstream.listen, 0)
    end

    response = read_response(client, method: method)
    :gen_tcp.close(client)
    response
  end

  defp rows(sql, args \\ []), do: Repo.query!(sql, args, log: false).rows

  defp snapshot,
    do:
      for(
        table <- ~w(users achievement_progresses achievement_unlock_events),
        do: rows("SELECT to_jsonb(t) FROM #{table} t ORDER BY id")
      )
end
