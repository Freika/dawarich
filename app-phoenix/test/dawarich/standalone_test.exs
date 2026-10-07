defmodule Dawarich.StandaloneTest do
  use Dawarich.DataCase, async: false

  import Plug.Conn
  import ExUnit.CaptureLog

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    hosted = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")
    config = Application.get_all_env(:dawarich)
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")

      if hosted, do: System.put_env("SELF_HOSTED", hosted), else: System.delete_env("SELF_HOSTED")

      for {key, value} <- config, do: Application.put_env(:dawarich, key, value)
    end)

    :ok
  end

  test "standalone selects native front and mandatory lifecycle while defaults remain unchanged" do
    env = %{"DAWARICH_RAILS" => "off", "PORT" => "4321", "BINDING" => "127.0.0.1"}
    assert {:native, {{127, 0, 0, 1}, 4321}} = plan = Dawarich.Application.plan(nil, env)

    refute Dawarich.RailsServer in Enum.map(
             Dawarich.Application.children(plan),
             &Supervisor.child_spec(&1, []).id
           )

    assert Dawarich.Front.upstream(plan) == nil
    assert Dawarich.Release.Lifecycle.mode(env) == {:ok, :native}

    assert Dawarich.Release.Lifecycle.mode(Map.put(env, "DAWARICH_PHOENIX_LIFECYCLE", "false")) ==
             {:ok, :native}

    assert Dawarich.Release.Lifecycle.mode(%{}) == {:ok, :rails}
    assert Dawarich.Application.plan(nil, %{}) == :none

    assert_raise ArgumentError, fn ->
      Dawarich.Application.plan(~w(rails runner arbitrary), env)
    end
  end

  test "standalone unknown routes and rejected envelopes are terminal logged and counted" do
    id = "standalone-test"
    parent = self()

    :telemetry.attach(
      id,
      [:dawarich, :standalone, :handback],
      fn event, measurements, metadata, _ -> send(parent, {event, measurements, metadata}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
    Application.put_env(:dawarich, :rails_upstream, nil)

    log =
      capture_log(fn ->
        for {path, status, reason} <- [
              {"/missing-native", 404, "missing_route"},
              {"/map?format=json", 422, "unsupported_envelope"}
            ] do
          conn = Plug.Test.conn(:get, path) |> DawarichWeb.Strangler.call([])
          assert conn.status == status
          assert conn.halted

          assert_receive {[:dawarich, :standalone, :handback], %{count: 1},
                          %{method: "GET", path: logged_path, reason: ^reason, status: ^status}}

          assert logged_path == conn.request_path
        end
      end)

    assert log =~ "[standalone.handback]"
    assert log =~ "missing_route"
    assert log =~ "unsupported_envelope"
  end

  test "standalone custom HTTP methods share the bounded OTHER telemetry label" do
    parent = self()
    id = "standalone-custom-methods"

    :telemetry.attach(
      id,
      [:dawarich, :standalone, :handback],
      fn _, _, metadata, _ ->
        send(parent, {:handback, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)

    for method <- ~w(REVIEWONE REVIEWTWO GET HEAD POST PUT PATCH DELETE OPTIONS) do
      label = if method in ~w(REVIEWONE REVIEWTWO), do: "OTHER", else: method

      log =
        capture_log(fn ->
          conn = Plug.Test.conn(method, "/review-missing") |> DawarichWeb.Strangler.call([])
          assert conn.status == 404
          assert_receive {:handback, %{method: ^label, status: 404, reason: "missing_route"}}
        end)

      assert log =~ method
    end
  end

  test "standalone proxy body replay and cable never open an upstream" do
    Application.put_env(:dawarich, :rails_upstream, nil)

    for fun <- [
          &DawarichWeb.RailsProxy.call(&1, nil),
          &DawarichWeb.RailsProxy.with_upstream(&1, nil, fn _, _ -> flunk("opened upstream") end),
          &DawarichWeb.Api.Body.replay(&1, "JSON Jason does not read"),
          &DawarichWeb.CableProxy.upgrade(&1, nil)
        ] do
      conn = Plug.Test.conn(:post, "/api/v1/points") |> assign(:api_tag, "api") |> fun.()
      assert conn.status == 422
      assert conn.halted
      assert Jason.decode!(conn.resp_body)["error"] == "Unprocessable Entity"
    end
  end

  test "standalone enables every auth flow and serves native sign in without opt ins" do
    Application.put_env(:dawarich, :phoenix_auth, [])

    assert DawarichWeb.AuthGate.flows() ==
             ~w(credentials recovery account api_keys two_factor otp account_link api_auth)

    Dawarich.State.put_registration_enabled(Repo, false)
    conn = Plug.Test.conn(:get, "/users/sign_in") |> DawarichWeb.AuthGate.call([])
    assert conn.status == 200
    assert String.contains?(conn.resp_body, "user[email]")
  end

  @tag :tmp_dir
  test "standalone serves precompiled public assets even with the test Rails environment", %{
    tmp_dir: root
  } do
    File.mkdir_p!(Path.join(root, "assets"))
    File.write!(Path.join(root, "assets/application.css"), "body{color:red}")

    Application.put_env(:dawarich, :public_files, %{
      env: %{
        "RAILS_ENV" => "test",
        "APPLICATION_PROTOCOL" => "http",
        "APPLICATION_HOSTS" => "localhost"
      },
      root: root
    })

    conn =
      Plug.Test.conn(:get, "/assets/application.css")
      |> Map.put(:req_headers, [{"host", "localhost"}])
      |> DawarichWeb.PublicFiles.call([])

    assert conn.status == 200
    assert conn.resp_body == "body{color:red}"
    assert conn.halted
  end

  test "standalone claims all registered native jobs and exports the handback counter" do
    assert Dawarich.Standalone.job_entries(%{"DAWARICH_RAILS" => "off"}) ==
             Dawarich.Jobs.Registry.entries()

    assert Dawarich.Standalone.job_entries(%{}) == []

    assert Enum.any?(
             Dawarich.Metrics.definitions(),
             &(&1.name == [:dawarich_standalone_handbacks])
           )
  end

  @tag :tmp_dir
  test "standalone resolves relative module imports through the precompiled asset manifest", %{
    tmp_dir: dir
  } do
    root = Path.join(dir, "public")
    assets = Path.join(root, "assets")
    File.mkdir_p!(Path.join(assets, "controllers"))
    File.write!(Path.join(assets, "controllers/example-digest.js"), "export const ready = true")

    File.write!(
      Path.join(assets, ".sprockets-manifest-fixture.json"),
      Jason.encode!(%{assets: %{"controllers/example.js" => "controllers/example-digest.js"}})
    )

    Application.put_env(:dawarich, :public_files, %{
      env: %{
        "RAILS_ENV" => "test",
        "APPLICATION_PROTOCOL" => "http",
        "APPLICATION_HOSTS" => "localhost"
      },
      root: root
    })

    for path <- ["/assets/controllers/example", "/assets/controllers/example.js"] do
      conn =
        Plug.Test.conn(:get, path)
        |> Map.put(:req_headers, [{"host", "localhost"}])
        |> DawarichWeb.PublicFiles.call([])

      assert conn.status == 200
      assert conn.resp_body == "export const ready = true"
      assert get_resp_header(conn, "content-type") == ["text/javascript"]
    end
  end
end
