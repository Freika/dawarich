defmodule DawarichWeb.StandaloneApiKeyFlowTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.{Accounts, Repo, TtlCache}
  alias Dawarich.Test.{RailsFormRequests, RailsUser}

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)
    names = ~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL)
    previous = Map.new(names, &{&1, System.get_env(&1)})
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "true")
    System.put_env("FORCE_SSL", "false")

    on_exit(fn ->
      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    users =
      for label <- ~w(actor other) do
        id = System.unique_integer([:positive])

        RailsUser.insert!(%{
          id: id,
          email: "standalone-key-#{label}@dawarich.test",
          api_key: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower),
          settings: %{"timezone" => "UTC", "locale" => "en", "onboarding_completed" => true}
        })
      end

    on_exit(fn ->
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)

      for user <- users do
        TtlCache.delete({DawarichWeb.RateLimit, key(user.id)})
        TtlCache.delete({DawarichWeb.RateLimit, user.api_key})
        Repo.query!("DELETE FROM users WHERE id=$1", [user.id], log: false)
      end
    end)

    [actor, other] = users
    %{actor: actor, other: other, session: RailsUser.session(actor.id)}
  end

  @tag :sweep_api_key
  test "standalone API key flow commits rotation revokes old credentials and preserves the session",
       c do
    other_before = snapshot(c.other.id)

    for identity <- [:password, :provider_otp] do
      if identity == :provider_otp do
        Repo.query!(
          "UPDATE users SET provider='openid_connect', uid='synthetic-provider', otp_required_for_login=true WHERE id=$1",
          [c.actor.id],
          log: false
        )
      end

      page = page(c.session)
      assert page.status == 200
      assert page.resp_body =~ "href=\"/settings/generate_api_key\""
      before = snapshot(c.actor.id)
      old = key(c.actor.id)
      TtlCache.put({DawarichWeb.RateLimit, old}, %{plan: 1}, 60_000)

      for form <- [:query, :bearer], do: assert(api_status(old, form) == 200)

      rotated = rotate(c.session, page)
      assert rotated.status == 302
      assert rotated.resp_body == ""
      assert get_resp_header(rotated, "location") == ["http://www.example.com/users/edit"]
      refute Map.has_key?(rotated.resp_cookies, "_dawarich_session")
      after_row = snapshot(c.actor.id)
      changed = changed(before, after_row)
      assert changed == ~w(api_key updated_at)
      current = key(c.actor.id)

      valid =
        is_binary(current) and Regex.match?(~r/\A[0-9a-f]{64}\z/, current) and current != old

      assert valid
      assert TtlCache.lookup({DawarichWeb.RateLimit, old}) == :error
      other_unchanged = snapshot(c.other.id) == other_before
      assert other_unchanged

      for form <- [:query, :bearer] do
        assert api_status(old, form) == 401
        assert api_status(current, form) == 200
        assert api_status(c.other.api_key, form) == 200
      end

      assert Accounts.from_session(c.session, DateTime.utc_now()).id == c.actor.id
      assert page(c.session).status == 200
    end

    page = page(c.session)
    before = snapshot(c.actor.id)
    current = key(c.actor.id)
    cache = {DawarichWeb.RateLimit, current}
    TtlCache.put(cache, %{plan: 1}, 60_000)

    Repo.query!(
      "ALTER TABLE users ADD CONSTRAINT sweep_key_update CHECK(id <> #{c.actor.id}) NOT VALID",
      [],
      log: false
    )

    try do
      rejected = rotate(c.session, page)
      assert rejected.status == 500
      assert rejected.resp_body == ""
      unchanged = snapshot(c.actor.id) == before
      assert unchanged
      assert TtlCache.lookup(cache) == {:ok, %{plan: 1}}
      assert api_status(current, :bearer) == 200
    after
      Repo.query!("ALTER TABLE users DROP CONSTRAINT sweep_key_update", [], log: false)
    end
  end

  @tag :api_key_fill_race
  test "rotation invalidation wins over an in-flight retired key plan lookup", c do
    old = key(c.actor.id)
    cache = {DawarichWeb.RateLimit, old}
    TtlCache.delete(cache)
    parent = self()
    handler = {__MODULE__, make_ref()}
    marker = make_ref()

    :ok =
      :telemetry.attach(
        handler,
        Repo.config()[:telemetry_prefix] ++ [:query],
        fn _, _, metadata, _ ->
          if Process.get(:rotation_cache_commit_probe) == marker and
               String.upcase(metadata.query) == "COMMIT" do
            TtlCache.fetch(cache, 120_000, fn -> "pro" end)
            send(parent, :commit_boundary_fill)
          end

          if Process.get(:retired_key_lookup) == marker and
               String.contains?(metadata.query, "api_key") do
            send(parent, {:lookup_selected, self()})

            receive do
              :release_lookup -> :ok
            after
              5_000 -> raise "lookup synchronization expired"
            end
          end
        end,
        nil
      )

    reader =
      Task.async(fn ->
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)
        Process.put(:retired_key_lookup, marker)
        DawarichWeb.RateLimit.plan(old)
      end)

    try do
      assert_receive {:lookup_selected, pid} when pid == reader.pid, 5_000
      Process.put(:rotation_cache_commit_probe, marker)
      assert rotate(c.session, page(c.session)).status == 302
      assert_received :commit_boundary_fill
      assert TtlCache.lookup(cache) == :error
      send(reader.pid, :release_lookup)
      assert Task.await(reader, 5_000) != nil
      assert TtlCache.lookup(cache) == :error
      assert DawarichWeb.RateLimit.plan(old) == nil
      assert Accounts.by_api_key(old) == nil
    after
      Process.delete(:rotation_cache_commit_probe)
      :telemetry.detach(handler)
      send(reader.pid, :release_lookup)
      if Process.alive?(reader.pid), do: Task.await(reader, 5_000)
    end
  end

  defp rotate(session, page) do
    [token] =
      page.resp_body
      |> LazyHTML.from_document()
      |> LazyHTML.query("meta[name='csrf-token']")
      |> LazyHTML.attribute("content")

    RailsFormRequests.post_form(
      session,
      "",
      [
        {"accept", "text/html"},
        {"x-csrf-token", token},
        {"referer", "http://www.example.com/users/edit"}
      ],
      "/settings/generate_api_key"
    )
  end

  defp page(session) do
    build_conn()
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("accept", "text/html")
    |> get("/users/edit")
  end

  defp api_status(key, :query) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> get("/api/v1/points?" <> URI.encode_query(%{"api_key" => key}))
    |> Map.fetch!(:status)
  end

  defp api_status(key, :bearer) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer " <> key)
    |> get("/api/v1/points")
    |> Map.fetch!(:status)
  end

  defp key(id) do
    [[key]] = Repo.query!("SELECT api_key FROM users WHERE id=$1", [id], log: false).rows
    key
  end

  defp snapshot(id) do
    [[row]] = Repo.query!("SELECT to_jsonb(users) FROM users WHERE id=$1", [id], log: false).rows
    row
  end

  defp changed(before, after_row),
    do: Enum.filter(Map.keys(before), &(before[&1] != after_row[&1])) |> Enum.sort()
end
