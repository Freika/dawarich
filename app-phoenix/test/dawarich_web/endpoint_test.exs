defmodule DawarichWeb.EndpointTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  import Dawarich.Test.RawHTTP

  setup do
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, nil) end)
    %{upstream: upstream}
  end

  defp serve(extra \\ []) do
    bandit =
      start_supervised!(
        {Bandit,
         [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0) ++ extra}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    port
  end

  test "a path Phoenix does not route goes to Puma with its body unread", ctx do
    client = connect(serve())

    send_raw(client, [
      "POST /settings/general HTTP/1.1\r\nHost: a\r\n",
      "Content-Type: application/x-www-form-urlencoded\r\nContent-Length: 17\r\n\r\nuser%5Btheme%5D=1"
    ])

    puma = accept(ctx.upstream)
    {head, rest} = read_head(puma)
    assert request_line(head) == "POST /settings/general HTTP/1.1"
    assert read_at_least(puma, rest, 17) == "user%5Btheme%5D=1"

    reply(puma, "HTTP/1.1 302 Found\r\nLocation: /settings\r\nContent-Length: 0\r\n\r\n")
    assert {302, headers, ""} = read_response(client)
    assert values(headers, "location") == ["/settings"]
  end

  test "a /cable upgrade goes to Puma as an upgrade", ctx do
    port = serve()
    client = ws_request(port, "/cable", [{"Origin", "http://127.0.0.1:#{port}"}])
    puma = accept(ctx.upstream)
    {head, _} = read_head(puma)

    assert request_line(head) == "GET /cable HTTP/1.1"
    assert header(head, "upgrade") == ["websocket"]
    reply(puma, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
    assert {404, _, ""} = read_response(client)
  end

  @tag :tmp_dir
  test "a crashed listener comes back on its port while its old socket lingers, and leaves Puma running",
       %{tmp_dir: tmp_dir} do
    pidfile = Path.join(tmp_dir, "puma.pid")
    {:ok, probe} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(probe)
    :ok = :gen_tcp.close(probe)
    puma_argv = ["sh", "-c", "echo $$ > #{pidfile}; exec sleep 60"]
    plan = {:proxy, %{public: {{127, 0, 0, 1}, port}, upstream: 1, puma_argv: puma_argv}}

    :ok = Supervisor.terminate_child(Dawarich.Supervisor, DawarichWeb.Endpoint)
    on_exit(fn -> Supervisor.restart_child(Dawarich.Supervisor, DawarichWeb.Endpoint) end)

    start_supervised!(
      %{
        id: :front,
        type: :supervisor,
        start:
          {Supervisor, :start_link, [Dawarich.Front.children(plan), [strategy: :one_for_one]]}
      },
      restart: :temporary
    )

    puma = wait_for_file(pidfile)
    bandit = listener()
    lingering = hold_listen_socket(bandit)
    Process.exit(bandit, :kill)

    assert restarted_soon?(bandit)
    :ok = :socket.close(lingering)
    assert accepting_soon?(port)
    assert File.read!(pidfile) == puma
    assert {_, 0} = System.cmd("kill", ["-0", String.trim(puma)])
  end

  defp hold_listen_socket(bandit) do
    {:listener, listener, _, _} = List.keyfind(Supervisor.which_children(bandit), :listener, 0)
    socket = Enum.find(Port.list(), &(Port.info(&1, :connected) == {:connected, listener}))
    {:ok, fd} = :inet.getfd(socket)
    {:ok, held} = :socket.open(fd, %{domain: :inet})
    held
  end

  defp wait_for_file(path, attempts \\ 200) do
    case File.read(path) do
      {:ok, content} when content != "" ->
        content

      _ when attempts > 0 ->
        Process.sleep(10)
        wait_for_file(path, attempts - 1)
    end
  end

  defp listener do
    Enum.find_value(Supervisor.which_children(DawarichWeb.Endpoint), fn
      {_, pid, :supervisor, [Bandit]} when is_pid(pid) -> pid
      _ -> nil
    end)
  end

  defp restarted_soon?(old, attempts \\ 200) do
    case listener() do
      pid when is_pid(pid) and pid != old ->
        true

      _ when attempts > 0 ->
        Process.sleep(10)
        restarted_soon?(old, attempts - 1)

      _ ->
        false
    end
  end

  defp accepting_soon?(port, attempts \\ 200) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 100) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} when attempts > 0 ->
        Process.sleep(10)
        accepting_soon?(port, attempts - 1)

      _ ->
        false
    end
  end

  test "stopping the listener lets an in-flight request finish and refuses new connections",
       ctx do
    {:ok, sup} =
      Supervisor.start_link(
        [
          {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
        ],
        strategy: :one_for_one
      )

    [{_, bandit, _, _}] = Supervisor.which_children(sup)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    client = connect(port)
    send_raw(client, "GET /slow HTTP/1.1\r\nHost: a\r\n\r\n")
    puma = accept(ctx.upstream)
    _ = read_head(puma)

    started = System.monotonic_time(:millisecond)
    stopping = Task.async(fn -> Supervisor.stop(sup) end)
    assert refused_soon?(port)

    reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\ndone")
    assert {200, _headers, "done"} = read_response(client)
    assert Task.await(stopping, 10_000) == :ok
    assert System.monotonic_time(:millisecond) - started < 5_000
  end

  test "stopping the production listener drains every acceptor within one shutdown budget", ctx do
    plan =
      {:proxy,
       %{
         public: {{127, 0, 0, 1}, 0},
         upstream: ctx.upstream.port,
         puma_argv: ~w(bundle exec puma)
       }}

    :ok = Supervisor.terminate_child(Dawarich.Supervisor, DawarichWeb.Endpoint)
    on_exit(fn -> Supervisor.restart_child(Dawarich.Supervisor, DawarichWeb.Endpoint) end)

    sup =
      start_supervised!(
        %{
          id: :production_listener,
          start:
            {Supervisor, :start_link,
             [Enum.drop(Dawarich.Front.children(plan), 1), [strategy: :one_for_one]]},
          type: :supervisor
        },
        restart: :temporary
      )

    on_exit(fn ->
      if Process.alive?(sup), do: Supervisor.stop(sup, :shutdown, 0)
    end)

    bandit = endpoint_bandit()
    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)

    clients =
      for _ <- 1..3 do
        client = connect(port)
        send_raw(client, "GET /slow HTTP/1.1\r\nHost: a\r\n\r\n")
        client
      end

    pumas = for _ <- clients, do: accept(ctx.upstream)
    assert acceptor_connection_count(bandit) == 3

    listener = ThousandIsland.Server.listener_pid(bandit)
    listener_ref = Process.monitor(listener)
    started = System.monotonic_time(:millisecond)
    stopping = Task.async(fn -> Supervisor.stop(sup) end)

    assert_receive {:DOWN, ^listener_ref, :process, ^listener, _reason}, 1_000
    assert refused(port)
    assert Task.yield(stopping, 6_500) == {:ok, :ok}
    assert System.monotonic_time(:millisecond) - started < 6_500

    Enum.each(clients ++ pumas, &:gen_tcp.close/1)
  end

  test "stopping the production listener closes a proxied cable connection normally", ctx do
    plan =
      {:proxy,
       %{
         public: {{127, 0, 0, 1}, 0},
         upstream: ctx.upstream.port,
         puma_argv: ~w(bundle exec puma)
       }}

    :ok = Supervisor.terminate_child(Dawarich.Supervisor, DawarichWeb.Endpoint)
    on_exit(fn -> Supervisor.restart_child(Dawarich.Supervisor, DawarichWeb.Endpoint) end)

    sup =
      start_supervised!(
        %{
          id: :production_listener,
          start:
            {Supervisor, :start_link,
             [Enum.drop(Dawarich.Front.children(plan), 1), [strategy: :one_for_one]]},
          type: :supervisor
        },
        restart: :temporary
      )

    on_exit(fn ->
      if Process.alive?(sup), do: Supervisor.stop(sup, :shutdown, 0)
    end)

    bandit = endpoint_bandit()
    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    client = ws_request(port, "/cable", [{"Origin", "http://127.0.0.1:#{port}"}])
    puma = accept(ctx.upstream)
    {head, _rest} = read_head(puma)
    key = head |> header("sec-websocket-key") |> hd()
    accept_key = Base.encode64(:crypto.hash(:sha, key <> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))

    reply(
      puma,
      "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: #{accept_key}\r\n\r\n"
    )

    {101, _headers, rest} = read_response_head(client)
    stopping = Task.async(fn -> Supervisor.stop(sup) end)

    assert {{:close, <<1000::16>>}, _rest} = ws_recv(client, rest)
    assert Task.await(stopping, 6_500) == :ok
  end

  defp endpoint_bandit do
    {:ok, bandit} = Bandit.PhoenixAdapter.bandit_pid(DawarichWeb.Endpoint)
    bandit
  end

  defp acceptor_connection_count(bandit) do
    bandit
    |> ThousandIsland.Server.acceptor_pool_supervisor_pid()
    |> ThousandIsland.AcceptorPoolSupervisor.acceptor_supervisor_pids()
    |> Enum.count(fn acceptor ->
      acceptor
      |> ThousandIsland.AcceptorSupervisor.connection_sup_pid()
      |> DynamicSupervisor.count_children()
      |> Map.fetch!(:active)
      |> Kernel.>(0)
    end)
  end

  defp refused(port) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 100) do
      {:error, _reason} ->
        true

      {:ok, socket} ->
        try do
          case :gen_tcp.send(socket, "GET /slow HTTP/1.1\r\nHost: a\r\n\r\n") do
            :ok ->
              case :gen_tcp.recv(socket, 0, 1_000) do
                {:error, reason} -> reason in [:closed, :econnreset]
                {:ok, _data} -> false
              end

            {:error, reason} ->
              reason in [:closed, :econnreset]
          end
        after
          :gen_tcp.close(socket)
        end
    end
  end

  defp refused_soon?(port, attempts \\ 200) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 100) do
      {:error, :econnrefused} ->
        true

      _ when attempts <= 0 ->
        false

      {:ok, socket} ->
        :gen_tcp.close(socket)
        Process.sleep(10)
        refused_soon?(port, attempts - 1)

      {:error, _other} ->
        Process.sleep(10)
        refused_soon?(port, attempts - 1)
    end
  end
end
