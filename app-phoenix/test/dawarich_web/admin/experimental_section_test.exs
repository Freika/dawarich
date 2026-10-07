defmodule DawarichWeb.Admin.ExperimentalSectionTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Phoenix.LiveViewTest, only: [render_component: 2]
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.{RailsUser, RawHTTP}
  alias DawarichWeb.{AdminLive.Instance, AdminWrites.Settings, RailsCsrf}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Repo.query!("DELETE FROM instance_settings", [], log: false)
    Dawarich.Experimental.refresh_map_matching(Repo, %{})
    previous = System.get_env("DAWARICH_RAILS")
    hosted = System.get_env("SELF_HOSTED")
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      :persistent_term.put({Dawarich.Experimental, Repo, :map_matching}, false)
      restore("DAWARICH_RAILS", previous)
      restore("SELF_HOSTED", hosted)
    end)

    RailsUser.insert!(%{
      id: 16010,
      email: "experimental-admin@example.invalid",
      admin: true,
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    %{
      context: %{
        self_hosted: true,
        oidc: false,
        env: %{},
        repo: Repo,
        locale: "en",
        current_user: Accounts.get(16010),
        rails_csrf_token: "CSRF",
        health: %{summary: %{}, gauges: %{"tables" => false}},
        two_factor: false,
        command: fn _ -> {:ok, 0} end
      },
      session: RailsUser.session(16010)
    }
  end

  test "section lists map matching with locked env-pinned toggles", c do
    env = %{
      "MAP_MATCHING_ENABLED" => "true",
      "MAP_MATCHING_SHADOW_MODE" => "false",
      "ATLAS_URL" => "http://atlas.example.invalid"
    }

    html = page(%{c.context | env: env})
    assert html =~ "Experimental features"
    assert html =~ "Pinned by MAP_MATCHING_ENABLED"
    assert html =~ "Pinned by MAP_MATCHING_SHADOW_MODE"
    assert html =~ "coordinates, timestamps, and GPS accuracy"
    assert html =~ "data-controller=\"map-matching-demo\""

    for key <- ~w(map_matching_enabled map_matching_shadow_mode) do
      assert Enum.count(
               LazyHTML.query(
                 LazyHTML.from_fragment(html),
                 "#instance_settings_#{key}[disabled]"
               )
             ) == 1

      refute html =~ "name=\"instance_settings[#{key}]\" value=\"false\""
    end

    assert Enum.count(LazyHTML.query(LazyHTML.from_fragment(html), "form form")) == 0

    assert Enum.count(
             LazyHTML.query(
               LazyHTML.from_fragment(html),
               "form[action='/admin/settings/test_map_matching']"
             )
           ) == 1
  end

  test "enabling without URL shows atlas_url_required", c do
    conn =
      request(c.session, "/admin/settings", [
        {"_method", "patch"},
        {"section", "experimental"},
        {"instance_settings[map_matching_enabled]", "true"}
      ])
      |> Settings.call(action: :instance, context: c.context)

    assert conn.status == 303
    assert flash(conn, "alert") == "Set an Atlas URL before enabling map matching."

    assert get_resp_header(conn, "location") == [
             "http://www.example.com/admin/settings?section=experimental"
           ]

    assert page(c.context) =~ "Set an Atlas URL before enabling map matching."
  end

  @tag :r1_admin_refresh
  test "R1 admin UI enable and disable refresh the completion gate without restart", c do
    alias Dawarich.Tracks.MapMatching.Enqueuer
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    assert :disabled = Enqueuer.defer(Repo, 0)

    for {value, result} <- [{"true", :deferred}, {"false", :disabled}] do
      conn =
        request(c.session, "/admin/settings", [
          {"_method", "patch"},
          {"section", "experimental"},
          {"instance_settings[atlas_url]", "http://atlas.example.invalid"},
          {"instance_settings[map_matching_enabled]", value}
        ])
        |> Settings.call(action: :instance, context: c.context)

      assert conn.status == 303
      assert flash(conn, "notice") == "Settings saved."
      assert Enqueuer.defer(Repo, 0) == result
      Dawarich.MapMatchingTasks.await!()
    end
  end

  test "test connection shows version", c do
    server = RawHTTP.listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)

    task =
      serve(server, [
        %{"data" => %{"status" => "ok", "capabilities" => %{"routing" => "up"}}},
        %{"data" => %{"version" => "0.6.0", "revision" => "abc123"}}
      ])

    env = %{"ATLAS_URL" => "http://127.0.0.1:#{server.port}"}

    conn =
      request(c.session, "/admin/settings/test_map_matching", [])
      |> DawarichWeb.Router.call(DawarichWeb.Router.init([]))

    assert conn.status == 303
    assert flash(conn, "alert") == "Save an Atlas URL first."

    conn =
      request(c.session, "/admin/settings/test_map_matching", [])
      |> Settings.call(action: :test_map_matching, context: %{c.context | env: env})

    assert conn.status == 303
    assert flash(conn, "notice") =~ "0.6.0 (abc123)"

    assert get_resp_header(conn, "location") == [
             "http://www.example.com/admin/settings?section=experimental"
           ]

    assert Task.await(task) == ["GET /api/v1/health HTTP/1.1", "GET /api/v1/version HTTP/1.1"]
  end

  test "non-admin gets the existing admin refusal", c do
    RailsUser.insert!(%{
      id: 16011,
      email: "experimental-member@example.invalid",
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    session = RailsUser.session(16011)

    conn =
      request(session, "/admin/settings/test_map_matching", [])
      |> DawarichWeb.Router.call(DawarichWeb.Router.init([]))

    assert conn.status == 303
    assert flash(conn, "alert") == "You are not authorized to perform this action."

    conn =
      Plug.Test.conn("GET", "/admin/settings?section=experimental")
      |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> put_req_header("accept", "text/html")
      |> DawarichWeb.Endpoint.call(DawarichWeb.Endpoint.init([]))

    assert conn.status == 303
    assert flash(conn, "alert") == "You are not authorized to perform this action."
    refute conn.resp_body =~ "map-matching-demo"

    refute DawarichWeb.AdminWritesGate.eligible?(
             request(session, "/admin/settings/test_map_matching", []),
             :test_map_matching,
             context: c.context
           )
  end

  test "failed connection warns without blocking settings save", c do
    server = RawHTTP.listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)

    task =
      serve(server, [
        %{"data" => %{"status" => "degraded", "capabilities" => %{"routing" => "down"}}},
        %{"data" => %{"version" => "0.6.0"}}
      ])

    url = "http://127.0.0.1:#{server.port}"

    conn =
      request(c.session, "/admin/settings", [
        {"_method", "patch"},
        {"section", "experimental"},
        {"instance_settings[atlas_url]", url},
        {"instance_settings[map_matching_enabled]", "true"}
      ])
      |> Settings.call(action: :instance, context: c.context)

    assert conn.status == 303
    assert flash(conn, "notice") == "Settings saved."

    conn =
      request(c.session, "/admin/settings/test_map_matching", [])
      |> Settings.call(action: :test_map_matching, context: c.context)

    assert flash(conn, "alert") =~ "routing_unavailable"
    assert Dawarich.Experimental.map_matching?(Repo, %{})
    Task.await(task)
  end

  test "connection action rejects invalid CSRF before calling Atlas", c do
    conn =
      request(c.session, "/admin/settings/test_map_matching", [], "invalid")
      |> Settings.call(action: :test_map_matching, context: c.context)

    assert conn.status == 422
    refute Map.has_key?(conn.private, :dawarich_rails_session_changes)
  end

  test "experimental copy and connection results exist in all seven locales", c do
    for locale <- ~w(en de fr es zh ca pl) do
      html = page(%{c.context | locale: locale})
      refute html =~ "translation missing"

      for key <-
            ~w(experimental.badge map_matching.privacy map_matching.example_caption map_matching.original_label map_matching.matched_label map_matching.example_alt map_matching.test map_matching.testing) do
        assert {:ok, value} =
                 Dawarich.I18n.t(locale, "admin.settings.show." <> key, %{}, fallback: false)

        assert is_binary(value) and value != ""
      end

      for key <- ~w(not_configured success routing_unavailable failure) do
        assert {:ok, value} =
                 Dawarich.I18n.t(
                   locale,
                   "admin.settings.test_map_matching." <> key,
                   %{"version" => "0.6.0", "error" => "routing_unavailable"},
                   fallback: false
                 )

        assert is_binary(value) and value != ""
      end
    end
  end

  test "Berlin demo mounts the native Stimulus bridge", c do
    html = page(c.context)

    assert Enum.count(
             LazyHTML.query(
               LazyHTML.from_fragment(html),
               "#map-matching-demo[phx-hook='RailsStimulus'][phx-update='ignore'][data-controller='map-matching-demo']"
             )
           ) == 1
  end

  defp page(context) do
    {:ok, data} = Instance.page(%{"section" => "experimental"}, context)
    render_component(&Instance.render/1, Map.merge(context, data))
  end

  defp request(session, path, values, token \\ nil) do
    body =
      URI.encode_query([
        {"authenticity_token", token || RailsCsrf.masked_token(session)} | values
      ])

    Plug.Test.conn("POST", path, body)
    |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("accept", "text/html")
  end

  defp flash(conn, kind),
    do: conn.private.dawarich_rails_session_changes["flash"]["flashes"][kind]

  defp restore(key, nil), do: System.delete_env(key)
  defp restore(key, value), do: System.put_env(key, value)

  defp serve(server, payloads) do
    Task.async(fn ->
      Enum.map(payloads, fn payload ->
        socket = RawHTTP.accept(server)
        {head, _} = RawHTTP.read_head(socket)
        line = RawHTTP.request_line(head)
        body = Jason.encode!(payload)

        RawHTTP.reply(
          socket,
          "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n" <>
            body
        )

        :gen_tcp.close(socket)
        line
      end)
    end)
  end
end
