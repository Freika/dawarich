defmodule DawarichWeb.OperatorConnectionSecurityTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test
  import Phoenix.LiveViewTest

  alias Dawarich.{Repo, Test.RailsUser}
  alias DawarichWeb.{Endpoint, SessionStore}

  @path "/settings/background_jobs"
  @health "instance-settings-phoenix-jobs"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    saved =
      Map.new(~w(SELF_HOSTED SIDEKIQ_USERNAME SIDEKIQ_PASSWORD JWT_SECRET_KEY), fn key ->
        {key, System.get_env(key)}
      end)

    upstream = Application.get_env(:dawarich, :rails_upstream)
    System.put_env("SELF_HOSTED", "false")
    System.put_env("SIDEKIQ_USERNAME", "synthetic-operator")
    System.put_env("SIDEKIQ_PASSWORD", "synthetic-password")
    System.put_env("JWT_SECRET_KEY", "synthetic-operator-security")
    Application.put_env(:dawarich, :rails_upstream, nil)
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    Dawarich.State.put_registration_enabled(Repo, false)

    RailsUser.insert!(%{
      id: 10001,
      email: "operator-security@example.invalid",
      admin: true,
      changelog_consent: 0,
      settings: %{"timezone" => "Europe/Berlin"}
    })

    on_exit(fn ->
      Enum.each(saved, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)

      Application.put_env(:dawarich, :rails_upstream, upstream)
    end)

    :ok
  end

  test "Cloud saved page tokens cannot authorize fresh logins and grants expire or revoke" do
    login = login()
    page = request(login, @path, "synthetic-operator:synthetic-password")
    assert page.status == 200
    context = connect_session(page, login)

    for _reconnect <- 1..2 do
      assert {:ok, view, html} = connected(page, context)
      assert html =~ @health
      assert :sys.get_state(view.pid).socket.assigns.current_user.admin
      GenServer.stop(view.pid)
    end

    fresh_login = login()
    refute fresh_login == login
    ordinary = request(fresh_login, "/settings/general")
    assert ordinary.status == 200
    fresh_context = connect_session(ordinary, fresh_login)

    refute ordinary.resp_cookies["_dawarich_phoenix"].value ==
             page.resp_cookies["_dawarich_phoenix"].value

    for credentials <- [nil, "synthetic-operator:wrong"] do
      assert request(fresh_login, @path, credentials).status == 401
      assert {:error, {:redirect, %{to: @path}}} = connected(page, fresh_context, credentials)
    end

    assert {:error, {:redirect, %{to: @path}}} =
             connected(page, connect_session(page, fresh_login))

    {:ok, decoded} = Phoenix.LiveView.Static.verify_token(Endpoint, token(page))
    refute Map.has_key?(decoded.session, "operator_authorization")
    refute Map.has_key?(decoded.session, "operator_grant")

    grant = context["operator_grant"]
    assert is_binary(grant)
    key = "dawarich:operator_grant:" <> grant
    assert {:ok, ttl} = Dawarich.Redis.cache_command(["TTL", key])
    assert ttl > 0 and ttl <= 3600
    assert {:ok, 1} = Dawarich.Redis.cache_command(["EXPIRE", key, "0"])
    assert {:error, {:redirect, %{to: @path}}} = connected(page, context)

    page = request(login, @path, "synthetic-operator:synthetic-password")
    context = connect_session(page, login)
    assert {:ok, view, _html} = connected(page, context)

    assert {:ok, 1} =
             Dawarich.Redis.cache_command([
               "DEL",
               "dawarich:operator_grant:" <> context["operator_grant"]
             ])

    send(view.pid, :navbar_refresh)
    assert_redirect(view, @path)
    assert {:error, {:redirect, %{to: @path}}} = connected(page, context)
  end

  test "operator channel reauthorizes built in clear flash before retaining health or processing events" do
    login = login()
    page = request(login, @path, "synthetic-operator:synthetic-password")
    context = connect_session(page, login)
    pid = channel(page, context)
    clear_flash(pid, "authorized")
    assert_receive %Phoenix.Socket.Reply{ref: "authorized", status: :ok}
    assert :sys.get_state(pid).socket.assigns.health
    assert :sys.get_state(pid).socket.assigns.current_user.admin

    Repo.query!("UPDATE users SET admin = false WHERE id = 10001", [], log: false)
    monitor = Process.monitor(pid)
    clear_flash(pid, "demoted")
    assert_receive %Phoenix.Socket.Message{event: "redirect", payload: %{to: @path}}
    assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}

    System.put_env("SELF_HOSTED", "true")
    Repo.query!("UPDATE users SET admin = true WHERE id = 10001", [], log: false)
    page = request(login, @path)
    pid = channel(page, connect_session(page, login))
    assert :sys.get_state(pid).socket.assigns.health
    Repo.query!("UPDATE users SET admin = false WHERE id = 10001", [], log: false)
    clear_flash(pid, "self-hosted-demoted")
    assert_receive %Phoenix.Socket.Reply{ref: "self-hosted-demoted", status: :ok}
    socket = :sys.get_state(pid).socket
    refute socket.assigns.current_user.admin
    assert socket.assigns.health == nil
    assert socket.redirected == nil

    refute socket.assigns
           |> DawarichWeb.SettingsLive.BackgroundJobs.render()
           |> Phoenix.HTML.Safe.to_iodata()
           |> IO.iodata_to_binary() =~ @health
  end

  def encode!(message), do: message

  defp channel(page, context) do
    [{_path, socket_module, _options}] = Endpoint.__sockets__()
    {channel, _options} = socket_module.__channel__("lv:operator-security")
    {:ok, decoded} = Phoenix.LiveView.Static.verify_token(Endpoint, token(page))
    topic = "lv:" <> decoded.id
    ref = make_ref()
    from = {self(), ref}

    pid =
      start_supervised!(%{
        id: make_ref(),
        start: {channel, :start_link, [{Endpoint, from}]},
        restart: :temporary
      })

    socket = %Phoenix.Socket{
      transport_pid: self(),
      serializer: __MODULE__,
      channel: channel,
      endpoint: Endpoint,
      private: %{connect_info: %{session: context}},
      topic: topic,
      join_ref: "join"
    }

    params = %{
      "session" => token(page),
      "static" => static_token(page),
      "params" => %{"_mounts" => 0},
      "url" => "http://localhost" <> @path,
      "caller" => {self(), self()}
    }

    send(pid, {Phoenix.Channel, params, from, socket})
    Phoenix.LiveView.Channel.ping(pid)
    assert_receive {^ref, {:ok, _reply}}
    pid
  end

  defp clear_flash(pid, ref) do
    state = :sys.get_state(pid)

    send(pid, %Phoenix.Socket.Message{
      topic: state.topic,
      event: "event",
      payload: %{"event" => "lv:clear-flash", "type" => "click", "value" => %{}},
      ref: ref,
      join_ref: "join"
    })

    try do
      Phoenix.LiveView.Channel.ping(pid)
    catch
      :exit, _reason -> :ok
    end
  end

  defp connected(page, context, credentials \\ nil) do
    headers = Enum.reject(page.req_headers, fn {key, _value} -> key == "authorization" end)

    headers =
      if credentials,
        do: [{"authorization", "Basic " <> Base.encode64(credentials)} | headers],
        else: headers

    page = %{page | req_headers: headers}

    Phoenix.LiveViewTest.__live__(
      put_private(page, :live_view_connect_info, %{session: context}),
      nil,
      []
    )
  end

  defp connect_session(page, login) do
    conn = conn(:get, "/phoenix/live/websocket") |> put_req_cookie("_dawarich_session", login)
    conn = %{conn | secret_key_base: page.secret_key_base}
    cookie = page.resp_cookies["_dawarich_phoenix"].value

    {_sid, session} =
      SessionStore.get(conn, cookie, SessionStore.init(Endpoint.session_options()))

    session
  end

  defp request(login, path, credentials \\ nil) do
    conn = conn(:get, path) |> put_req_cookie("_dawarich_session", login)

    conn =
      if credentials,
        do: put_req_header(conn, "authorization", "Basic " <> Base.encode64(credentials)),
        else: conn

    Endpoint.call(conn, Endpoint.init([]))
  end

  defp login do
    session_id = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    RailsUser.cookie(RailsUser.session(10001, %{"session_id" => session_id}))
  end

  defp token(page), do: attribute(page, "data-phx-session")
  defp static_token(page), do: attribute(page, "data-phx-static")
  defp attribute(page, name), do: Regex.run(~r/#{name}="([^"]+)"/, page.resp_body) |> Enum.at(1)
end
