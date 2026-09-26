defmodule DawarichWeb.EndpointTest do
  use ExUnit.Case, async: false

  import Dawarich.Test.RawHTTP

  setup do
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {"127.0.0.1", upstream.port})
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
    _client = ws_request(port, "/cable", [{"Origin", "http://127.0.0.1:#{port}"}])
    puma = accept(ctx.upstream)
    {head, _} = read_head(puma)

    assert request_line(head) == "GET /cable HTTP/1.1"
    assert header(head, "upgrade") == ["websocket"]
  end

  test "a crashed listener comes back on its port and leaves Puma running" do
    pidfile = Path.join(System.tmp_dir!(), "a2-puma-#{System.unique_integer([:positive])}.pid")
    {:ok, probe} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(probe)
    :ok = :gen_tcp.close(probe)
    puma_argv = ["sh", "-c", "echo $$ > #{pidfile}; exec sleep 60"]
    plan = {:proxy, %{public: {{127, 0, 0, 1}, port}, upstream: 1, puma_argv: puma_argv}}

    :ok = Supervisor.terminate_child(Dawarich.Supervisor, DawarichWeb.Endpoint)
    on_exit(fn -> Supervisor.restart_child(Dawarich.Supervisor, DawarichWeb.Endpoint) end)
    {:ok, sup} = Supervisor.start_link(Dawarich.Front.children(plan), strategy: :one_for_one)

    puma = wait_for_file(pidfile)
    bandit = listener()
    Process.exit(bandit, :kill)

    assert restarted_soon?(bandit)
    assert accepting_soon?(port)
    assert File.read!(pidfile) == puma
    assert {_, 0} = System.cmd("kill", ["-0", String.trim(puma)])

    :ok = Supervisor.stop(sup)
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
