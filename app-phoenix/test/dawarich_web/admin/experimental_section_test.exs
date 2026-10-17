defmodule DawarichWeb.Admin.ExperimentalSectionTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Phoenix.LiveViewTest, only: [render_component: 2]
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.{RailsUser, RawHTTP}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Admin.Instance

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Repo.query!("DELETE FROM instance_settings", [], log: false)
    Dawarich.Experimental.refresh_map_matching(Repo, %{})
    previous = System.get_env("DAWARICH_RAILS")
    hosted = System.get_env("SELF_HOSTED")
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      Dawarich.Experimental.cache_map_matching(Repo, false)
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
      }
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
    assert html =~ ~s(phx-hook="MapMatchingDemo")

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
               "button#test-map-matching[phx-click=test_map_matching]"
             )
           ) == 1
  end

  test "enabling without URL shows atlas_url_required", c do
    assert Instance.save(scope(), experimental(%{"map_matching_enabled" => "true"}), opts()) ==
             {:error, {:invalid, "Set an Atlas URL before enabling map matching."}}

    assert page(c.context) =~ "Set an Atlas URL before enabling map matching."
  end

  @tag :r1_admin_refresh
  test "R1 admin UI enable and disable refresh the completion gate without restart" do
    alias Dawarich.Tracks.MapMatching.Enqueuer
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    assert :disabled = Enqueuer.defer(Repo, 0)

    for {value, result} <- [{"true", :deferred}, {"false", :disabled}] do
      params =
        experimental(%{
          "atlas_url" => "http://atlas.example.invalid",
          "map_matching_enabled" => value
        })

      assert Instance.save(scope(), params, opts()) == {:ok, :saved}
      assert Enqueuer.defer(Repo, 0) == result
      Dawarich.MapMatchingTasks.await!()
    end
  end

  test "test connection shows version" do
    server = RawHTTP.listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)

    task =
      serve(server, [
        %{"data" => %{"status" => "ok", "capabilities" => %{"routing" => "up"}}},
        %{"data" => %{"version" => "0.6.0", "revision" => "abc123"}}
      ])

    scope = Dawarich.Accounts.Scope.for_user(Accounts.get(16010), "en")

    assert Dawarich.Admin.Instance.test_map_matching(scope, env: %{"SELF_HOSTED" => "true"}) ==
             {:alert, "admin.settings.test_map_matching.not_configured", %{}}

    env = %{"SELF_HOSTED" => "true", "ATLAS_URL" => "http://127.0.0.1:#{server.port}"}

    assert Dawarich.Admin.Instance.test_map_matching(scope, env: env) ==
             {:notice, "admin.settings.test_map_matching.success",
              %{"version" => "0.6.0 (abc123)"}}

    assert Task.await(task) == ["GET /api/v1/health HTTP/1.1", "GET /api/v1/version HTTP/1.1"]
  end

  test "non-admin gets the existing admin refusal and Atlas is never called", _c do
    RailsUser.insert!(%{
      id: 16011,
      email: "experimental-member@example.invalid",
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    session = RailsUser.session(16011)
    scope = Dawarich.Accounts.Scope.for_user(Accounts.get(16011), "en")

    assert Dawarich.Admin.Instance.test_map_matching(scope,
             env: %{"SELF_HOSTED" => "true", "ATLAS_URL" => "http://127.0.0.1:1"}
           ) == {:error, :unauthorized}

    conn =
      Plug.Test.conn("GET", "/admin/settings?section=experimental")
      |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> put_req_header("accept", "text/html")
      |> DawarichWeb.Endpoint.call(DawarichWeb.Endpoint.init([]))

    assert conn.status == 404
    assert get_resp_header(conn, "location") == []
    refute conn.resp_body =~ "map-matching-demo"
  end

  test "failed connection warns without blocking settings save" do
    server = RawHTTP.listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)

    task =
      serve(server, [
        %{"data" => %{"status" => "degraded", "capabilities" => %{"routing" => "down"}}},
        %{"data" => %{"version" => "0.6.0"}}
      ])

    url = "http://127.0.0.1:#{server.port}"
    params = experimental(%{"atlas_url" => url, "map_matching_enabled" => "true"})
    assert Instance.save(scope(), params, opts()) == {:ok, :saved}

    assert {:alert, "admin.settings.test_map_matching.failure",
            %{"error" => "routing_unavailable"}} = Instance.test_map_matching(scope(), opts())

    assert Dawarich.Experimental.map_matching?(Repo, %{})
    Task.await(task)
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

  test "Berlin demo mounts the native map hook with both route buttons", c do
    html = page(c.context)

    assert Enum.count(
             LazyHTML.query(
               LazyHTML.from_fragment(html),
               "#map-matching-demo[phx-hook='MapMatchingDemo'][phx-update='ignore']:not([data-controller]) [data-demo-map]"
             )
           ) == 1

    assert Enum.count(
             LazyHTML.query(LazyHTML.from_fragment(html), "#map-matching-demo button[data-mode]")
           ) == 2
  end

  defp page(context) do
    {:ok, data} = Dawarich.Admin.InstancePage.load(context.repo, context.env)

    render_component(&DawarichWeb.AdminExperimental.section/1,
      locale: context.locale,
      data: data,
      testing: MapSet.new(),
      saves: 0
    )
  end

  defp scope, do: Scope.for_user(Accounts.get(16010), "en")
  defp opts, do: [env: %{"SELF_HOSTED" => "true"}, command: fn _ -> {:ok, 0} end]

  defp experimental(settings),
    do: %{"section" => "experimental", "instance_settings" => settings}

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
