defmodule DawarichWeb.StranglerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias DawarichWeb.Strangler
  alias Dawarich.{Repo, Release.Lifecycle}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.RawHTTP

  setup context do
    if context[:a12h_route] do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
      keys = ~w(SELF_HOSTED DAWARICH_PHOENIX_LIFECYCLE DAWARICH_RAILS_SLICES)
      saved = Map.new(keys, &{&1, System.get_env(&1)})
      routes = Application.get_env(:dawarich, :rails_routes, [])
      upstream = Application.get_env(:dawarich, :rails_upstream)
      server = RawHTTP.listen()
      parent = self()
      start_supervised!({Task, fn -> upstream_loop(server, parent) end})
      Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, server.port})
      Application.put_env(:dawarich, :rails_routes, [])
      System.put_env("SELF_HOSTED", "true")
      System.delete_env("DAWARICH_RAILS_SLICES")
      Ownership.put!(Repo, "command:a12h_handoff", :oban, pinned: true)

      on_exit(fn ->
        :gen_tcp.close(server.listen)
        Application.put_env(:dawarich, :rails_routes, routes)
        Application.put_env(:dawarich, :rails_upstream, upstream)

        Enum.each(saved, fn {key, value} ->
          if value, do: System.put_env(key, value), else: System.delete_env(key)
        end)
      end)
    end

    :ok
  end

  def boom(_conn, _params), do: exit(:timeout)

  test "a rails_gate that is not a {module, function} tuple fails closed" do
    route = %{rails_gate: &Kernel.is_nil/1, path_params: %{}}
    refute Strangler.gate_open?(route, %Plug.Conn{})
  end

  test "an exit from the gate hands the request to Puma" do
    route = %{rails_gate: {__MODULE__, :boom}, path_params: %{}}
    conn = %Plug.Conn{request_path: "/trips"}

    Logger.put_module_level(Strangler, :info)
    on_exit(fn -> Logger.delete_module_level(Strangler) end)

    log =
      capture_log(fn ->
        refute Strangler.gate_open?(route, conn)
      end)

    assert log =~ "[strangler] /trips handed to Rails: :timeout"
  end

  test "an owned HEAD request keeps its original method for the rate limiter" do
    conn = Plug.Test.conn(:head, "http://www.example.com/stats") |> Strangler.call([])
    assert conn.private.dawarich_method == "HEAD"
    assert conn.method == "GET"
  end

  @tag a12h_route: true
  test "lifecycle preserves route rails_key hand-back" do
    route =
      Phoenix.Router.route_info(
        DawarichWeb.Router,
        "POST",
        "/settings/users/import",
        "www.example.com"
      )

    assert route.rails_key == "user_data"
    Application.put_env(:dawarich, :rails_routes, ["user_data"])
    hand_back!("/settings/users/import?source=a12h", "synthetic=a12h&unchanged=1")
  end

  @tag a12h_route: true
  test "lifecycle preserves Rails slice hand-back" do
    System.put_env("DAWARICH_RAILS_SLICES", "api_places")

    route =
      Phoenix.Router.route_info(DawarichWeb.Router, "POST", "/api/v1/places", "www.example.com")

    assert route.slice == :api_places
    hand_back!("/api/v1/places?source=a12h", ~s({"name":"a12h synthetic place"}))
  end

  defp hand_back!(path, body) do
    before = snapshot()
    auth = Application.get_env(:dawarich, :phoenix_auth)
    auth_env = System.get_env("DAWARICH_PHOENIX_AUTH")

    for {flag, mode} <- [{"false", :rails}, {"true", :native}] do
      System.put_env("DAWARICH_PHOENIX_LIFECYCLE", flag)
      assert Lifecycle.mode() == {:ok, mode}

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
        |> Plug.Conn.put_req_header("content-length", Integer.to_string(byte_size(body)))
        |> Phoenix.ConnTest.dispatch(DawarichWeb.Endpoint, :post, path, body)

      assert conn.status == 218
      assert conn.resp_body == "Rails"
      assert_receive {:a12h_upstream, line, received_body}
      assert line == "POST #{path} HTTP/1.1"
      assert received_body == body
      refute conn.private[:dawarich_method]
      assert snapshot() == before
      assert Ownership.lock(Repo, "command:a12h_handoff") == :oban
      assert Ownership.lock(Repo, "command:a12h_unowned") == :sidekiq
      assert Application.get_env(:dawarich, :phoenix_auth) == auth
      assert System.get_env("DAWARICH_PHOENIX_AUTH") == auth_env
    end
  end

  defp snapshot do
    Repo.query!(
      "SELECT (SELECT count(*) FROM users), (SELECT count(*) FROM imports), (SELECT count(*) FROM places), (SELECT count(*) FROM job_outbox), (SELECT count(*) FROM oban.oban_jobs)",
      [],
      log: false
    ).rows ++
      Repo.query!(
        "SELECT key,owner,pinned,updated_at,updated_by FROM phoenix.job_owners ORDER BY key",
        [],
        log: false
      ).rows
  end

  defp upstream_loop(server, parent) do
    socket = RawHTTP.accept(server)
    {head, rest} = RawHTTP.read_head(socket)
    [size] = RawHTTP.header(head, "content-length")
    length = String.to_integer(size)
    body = binary_part(RawHTTP.read_at_least(socket, rest, length), 0, length)
    send(parent, {:a12h_upstream, RawHTTP.request_line(head), body})
    RawHTTP.reply(socket, "HTTP/1.1 218 Rails\r\ncontent-length: 5\r\n\r\nRails")
    :gen_tcp.close(socket)
    upstream_loop(server, parent)
  end
end
