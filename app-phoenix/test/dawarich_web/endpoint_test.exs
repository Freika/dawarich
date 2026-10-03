defmodule DawarichWeb.EndpointTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  import Dawarich.Test.RawHTTP
  import ExUnit.CaptureLog

  setup do
    upstream = listen()

    previous =
      Map.new([:rails_upstream, :rails_routes], &{&1, Application.fetch_env(:dawarich, &1)})

    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, configured} -> Application.put_env(:dawarich, key, configured)
          :error -> Application.delete_env(:dawarich, key)
        end
      end
    end)

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

  test "a handed-back /cable upgrade goes to Puma as an upgrade", ctx do
    Application.put_env(:dawarich, :rails_routes, ["cable"])
    port = serve()
    client = ws_request(port, "/cable", [{"Origin", "http://127.0.0.1:#{port}"}])
    puma = accept(ctx.upstream)
    {head, _} = read_head(puma)

    assert request_line(head) == "GET /cable HTTP/1.1"
    assert header(head, "upgrade") == ["websocket"]
    reply(puma, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
    assert {404, _, ""} = read_response(client)
  end

  test "Phoenix answers /notifications itself" do
    client = connect(serve())
    send_raw(client, "GET /notifications HTTP/1.1\r\nHost: a\r\n\r\n")

    assert {302, headers, _body} = read_response(client)
    assert values(headers, "location") == ["http://a/users/sign_in"]
    assert values(headers, "x-frame-options") == ["SAMEORIGIN"]
  end

  defp answered_by_puma(port, upstream, request) do
    client = connect(port)
    send_raw(client, request)

    puma =
      case :gen_tcp.accept(upstream.listen, 5_000) do
        {:ok, socket} ->
          socket

        {:error, reason} ->
          flunk(
            "Puma did not receive #{request |> String.split("\r\n") |> hd()}: #{inspect(reason)}"
          )
      end

    {head, _rest} = read_head(puma)
    reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\npuma")
    assert {200, _headers, "puma"} = read_response(client)
    request_line(head)
  end

  defp answered_by_phoenix(port, request) do
    client = connect(port)
    send_raw(client, request)
    {status, _headers, _body} = read_response(client)
    status
  end

  defp with_info_log(fun) do
    previous = Logger.level()
    Logger.configure(level: :info)

    try do
      capture_log([level: :info], fun)
    after
      Logger.configure(level: previous)
    end
  end

  test "Rails answers what a browser page is not asked for: JSON, XHR, a format", ctx do
    port = serve()
    get = fn target, headers -> "GET #{target} HTTP/1.1\r\nHost: a\r\n#{headers}\r\n" end

    for {target, headers} <- [
          {"/notifications", "Accept: application/json\r\n"},
          {"/notifications", "Accept: text/html, application/json\r\n"},
          {"/notifications", "Accept: text/plain\r\n"},
          {"/notifications", "Accept: application/xhtml+xml\r\n"},
          {"/notifications", "X-Requested-With: XMLHttpRequest\r\n"},
          {"/notifications/5.json", ""},
          {"/notifications?format=json", ""},
          {"/notifications?page=2&form%61t=json", ""}
        ],
        do: assert(answered_by_puma(port, ctx.upstream, get.(target, headers)) =~ target)

    for {target, headers} <- [
          {"/notifications", ""},
          {"/notifications", "Accept: */*\r\n"},
          {"/notifications", "Accept: application/json, */*;q=0.1\r\n"},
          {"/notifications",
           "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\n"},
          {"/notifications",
           "Accept: text/vnd.turbo-stream.html, text/html, application/xhtml+xml\r\n"},
          {"/notifications/5", "Accept: text/html\r\n"}
        ],
        do: assert(answered_by_phoenix(port, get.(target, headers)) == 302, target <> headers)
  end

  test "the no-socket fallbacks of the notification pages post to Puma", ctx do
    port = serve()

    for target <- ~w(/notifications/mark_as_read /notifications/destroy_all /notifications/5) do
      body = "_method=post&authenticity_token=x"

      request =
        "POST #{target} HTTP/1.1\r\nHost: a\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"

      assert answered_by_puma(port, ctx.upstream, request) == "POST #{target} HTTP/1.1"
    end
  end

  test "a route handed back to Rails goes to Puma although Phoenix routes it", ctx do
    Application.put_env(:dawarich, :rails_routes, ["notifications"])
    client = connect(serve())
    send_raw(client, "GET /notifications HTTP/1.1\r\nHost: a\r\n\r\n")

    puma = accept(ctx.upstream)
    {head, _} = read_head(puma)
    assert request_line(head) == "GET /notifications HTTP/1.1"
    reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
    assert {200, _headers, "ok"} = read_response(client)
  end

  test "Phoenix answers the imports and exports lists itself" do
    port = serve()

    for target <-
          ~w(/imports /imports/new /exports /imports?page=2 /exports?order_by=asc&sort_by=name) do
      assert answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302, target
    end
  end

  test "unowned import methods and export writes with unsafe admission go to Puma", ctx do
    port = serve()

    for target <-
          ~w(/imports/5 /imports/5/edit /imports/5/download /imports/5/extraction /imports.json /exports.json /imports?format=json /imports/5?format=json /imports/5/download?format=json /exports/5) do
      assert answered_by_puma(port, ctx.upstream, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") ==
               "GET #{target} HTTP/1.1"
    end

    for {method, target} <- [
          {"PUT", "/imports/5"},
          {"PUT", "/imports"},
          {"PATCH", "/imports/5/extraction"},
          {"DELETE", "/imports"},
          {"POST", "/imports/5/download"},
          {"POST", "/imports/direct_uploads"},
          {"PUT", "/imports/uploads/token"},
          {"POST", "/exports"},
          {"POST", "/exports/5"},
          {"DELETE", "/exports/5"},
          {"POST", "/settings/background_jobs?job_name=start_immich_import"}
        ] do
      body = "_method=delete&authenticity_token=x"

      request =
        "#{method} #{target} HTTP/1.1\r\nHost: a\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"

      assert answered_by_puma(port, ctx.upstream, request) == "#{method} #{target} HTTP/1.1"
    end
  end

  test "router lists exactly the owned import and export methods" do
    actual =
      DawarichWeb.Router.__routes__()
      |> Enum.filter(&String.starts_with?(&1.path, ["/imports", "/exports"]))
      |> Enum.map(&{String.upcase(to_string(&1.verb)), &1.path})
      |> Enum.sort()

    expected = [
      {"GET", "/imports"},
      {"GET", "/imports/new"},
      {"GET", "/imports/:id"},
      {"GET", "/imports/:id/download"},
      {"POST", "/imports"},
      {"POST", "/imports/:id"},
      {"PATCH", "/imports/:id"},
      {"DELETE", "/imports/:id"},
      {"POST", "/imports/:id/extraction"},
      {"DELETE", "/imports/:id/extraction"},
      {"GET", "/exports"},
      {"POST", "/exports"}
    ]

    assert actual == Enum.sort(expected)
  end

  test "signed-out import writes reach Puma with their body", ctx do
    port = serve()
    body = "import%5Bname%5D=x"

    for {method, target} <- [
          {"POST", "/imports"},
          {"POST", "/imports/5"},
          {"PATCH", "/imports/5"},
          {"DELETE", "/imports/5"},
          {"POST", "/imports/5/extraction"},
          {"DELETE", "/imports/5/extraction"}
        ] do
      client = connect(port)

      send_raw(
        client,
        "#{method} #{target} HTTP/1.1\r\nHost: a\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"
      )

      puma = accept(ctx.upstream)
      {head, rest} = read_head(puma)
      assert request_line(head) == "#{method} #{target} HTTP/1.1"
      assert read_at_least(puma, rest, byte_size(body)) == body
      reply(puma, "HTTP/1.1 302 Found\r\nLocation: /users/sign_in\r\nContent-Length: 0\r\n\r\n")
      assert {302, _headers, ""} = read_response(client)
    end
  end

  test "a foreign or non-GPX import's pages, download and writes go to Puma", ctx do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    alias Dawarich.Test.{RailsUser, ImportsExportsSeeds}
    RailsUser.insert!(%{id: 7691, email: "tcp-owner@example.test"})
    RailsUser.insert!(%{id: 7692, email: "tcp-foreign@example.test"})
    ImportsExportsSeeds.import!(%{id: 769_101, user_id: 7691, name: "private-owner.gpx"})
    ImportsExportsSeeds.import!(%{id: 769_102, user_id: 7692, name: "own.geojson", source: 6})
    session = RailsUser.session(7692)
    cookie = RailsUser.cookie(session)
    token = DawarichWeb.RailsCsrf.masked_token(session)
    port = serve()

    for id <- [769_101, 769_102],
        target <- ["/imports/#{id}", "/imports/#{id}/edit", "/imports/#{id}/download"] do
      request = "GET #{target} HTTP/1.1\r\nHost: a\r\nCookie: _dawarich_session=#{cookie}\r\n\r\n"
      assert answered_by_puma(port, ctx.upstream, request) == "GET #{target} HTTP/1.1"
    end

    body = "import%5Bname%5D=stolen"

    for id <- [769_101, 769_102],
        {method, target} <- [
          {"PATCH", "/imports/#{id}"},
          {"POST", "/imports/#{id}"},
          {"DELETE", "/imports/#{id}"},
          {"POST", "/imports/#{id}/extraction"},
          {"DELETE", "/imports/#{id}/extraction"}
        ] do
      request =
        "#{method} #{target} HTTP/1.1\r\nHost: a\r\nCookie: _dawarich_session=#{cookie}\r\n" <>
          "X-CSRF-Token: #{token}\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"

      assert answered_by_puma(port, ctx.upstream, request) == "#{method} #{target} HTTP/1.1"
    end

    assert [["private-owner.gpx", 2], ["own.geojson", 2]] ==
             Dawarich.Repo.query!("SELECT name,status FROM imports ORDER BY id", [], log: false).rows
  end

  test "DAWARICH_RAILS_ROUTES=imports hands every import route and method back", ctx do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    alias Dawarich.Test.{RailsUser, ImportsExportsSeeds}
    RailsUser.insert!(%{id: 7693, email: "tcp-handback@example.test"})
    ImportsExportsSeeds.import!(%{id: 769_301, user_id: 7693, name: "handback.gpx"})
    session = RailsUser.session(7693)
    cookie = "Cookie: _dawarich_session=#{RailsUser.cookie(session)}\r\n"
    token = "X-CSRF-Token: #{DawarichWeb.RailsCsrf.masked_token(session)}\r\n"
    port = serve()

    assert answered_by_phoenix(port, "GET /imports/769301 HTTP/1.1\r\nHost: a\r\n#{cookie}\r\n") ==
             200

    Application.put_env(:dawarich, :rails_routes, ["imports"])
    body = "import%5Bname%5D=renamed.gpx"

    for {method, target} <- [
          {"GET", "/imports"},
          {"GET", "/imports/new"},
          {"GET", "/imports/769301"},
          {"GET", "/imports/769301/edit"},
          {"GET", "/imports/769301/download"},
          {"POST", "/imports"},
          {"POST", "/imports/769301"},
          {"PATCH", "/imports/769301"},
          {"DELETE", "/imports/769301"},
          {"POST", "/imports/769301/extraction"},
          {"DELETE", "/imports/769301/extraction"}
        ] do
      request =
        "#{method} #{target} HTTP/1.1\r\nHost: a\r\n#{cookie}#{token}" <>
          "Content-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"

      assert answered_by_puma(port, ctx.upstream, request) == "#{method} #{target} HTTP/1.1"
    end

    assert [["handback.gpx", 2]] ==
             Dawarich.Repo.query!("SELECT name,status FROM imports", [], log: false).rows
  end

  test "DAWARICH_RAILS_ROUTES hands the imports and exports lists back with their query", ctx do
    Application.put_env(:dawarich, :rails_routes, ["imports", "exports"])
    port = serve()

    for target <- ~w(/imports /imports?order_by=asc&page=2&sort_by=name /exports?page=2) do
      assert answered_by_puma(port, ctx.upstream, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") ==
               "GET #{target} HTTP/1.1"
    end

    body = "start_at=x&file_format=json"

    post =
      "POST /exports HTTP/1.1\r\nHost: a\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
        "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"

    log =
      with_info_log(fn ->
        assert answered_by_puma(port, ctx.upstream, post) == "POST /exports HTTP/1.1"
      end)

    refute log =~ "[form]"
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

    on_exit(fn ->
      {:ok, _} = Supervisor.restart_child(Dawarich.Supervisor, DawarichWeb.Endpoint)
    end)

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

    on_exit(fn ->
      {:ok, _} = Supervisor.restart_child(Dawarich.Supervisor, DawarichWeb.Endpoint)
    end)

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
    live_socket = Process.whereis(DawarichWeb.Endpoint.Phoenix.LiveView.Socket)
    live_socket_ref = Process.monitor(live_socket)
    started = System.monotonic_time(:millisecond)
    stopping = Task.async(fn -> Supervisor.stop(sup) end)

    assert_receive {:DOWN, ^listener_ref, :process, ^listener, _reason}, 1_000
    assert refused(port)
    assert Task.yield(stopping, 6_500) == {:ok, :ok}
    assert_receive {:DOWN, ^live_socket_ref, :process, ^live_socket, _reason}, 1_000
    assert System.monotonic_time(:millisecond) - started < 6_500

    Enum.each(clients ++ pumas, &:gen_tcp.close/1)
  end

  test "stopping the production listener closes a proxied cable connection normally", ctx do
    Application.put_env(:dawarich, :rails_routes, ["cable"])

    plan =
      {:proxy,
       %{
         public: {{127, 0, 0, 1}, 0},
         upstream: ctx.upstream.port,
         puma_argv: ~w(bundle exec puma)
       }}

    :ok = Supervisor.terminate_child(Dawarich.Supervisor, DawarichWeb.Endpoint)

    on_exit(fn ->
      {:ok, _} = Supervisor.restart_child(Dawarich.Supervisor, DawarichWeb.Endpoint)
    end)

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
    live_socket = Process.whereis(DawarichWeb.Endpoint.Phoenix.LiveView.Socket)
    live_socket_ref = Process.monitor(live_socket)
    stopping = Task.async(fn -> Supervisor.stop(sup) end)

    assert {{:close, <<1000::16>>}, _rest} = ws_recv(client, rest)
    assert Task.await(stopping, 6_500) == :ok
    assert_receive {:DOWN, ^live_socket_ref, :process, ^live_socket, _reason}, 1_000
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

  test "Phoenix answers the stats and digest pages itself" do
    port = serve()

    for target <-
          ~w(/stats /stats/2024 /stats/2024/3 /stats/2024/03 /stats/2024/12 /digests /digests/2024) do
      assert answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302, target
    end
  end

  test "stats and digest paths outside Rails' constraints, and every other method, go to Puma",
       ctx do
    port = serve()

    for target <-
          ~w(/stats/abcd /stats/202 /stats/20245 /stats/update_all /stats/2024/0 /stats/2024/00 /stats/2024/13 /stats/2024/1a /digests/new /digests/24 /stats/2024.json),
        do:
          assert(
            answered_by_puma(port, ctx.upstream, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") ==
              "GET #{target} HTTP/1.1"
          )

    for {method, target} <- [
          {"PUT", "/stats/update_all"},
          {"PUT", "/stats/2024/3/update"},
          {"PUT", "/stats/2024/all/update"},
          {"PATCH", "/stats/2024/3/sharing"},
          {"POST", "/digests?year=2023"},
          {"DELETE", "/digests/2023"},
          {"PATCH", "/digests/2023/sharing"}
        ] do
      body = "authenticity_token=x"

      request =
        "#{method} #{target} HTTP/1.1\r\nHost: a\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"

      assert answered_by_puma(port, ctx.upstream, request) == "#{method} #{target} HTTP/1.1"
    end
  end

  test "DAWARICH_RAILS_ROUTES hands the stats and digest pages back", ctx do
    Application.put_env(:dawarich, :rails_routes, ["stats", "digests"])
    port = serve()

    for target <- ~w(/stats /stats/2024/3 /digests/2024),
        do:
          assert(
            answered_by_puma(port, ctx.upstream, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") ==
              "GET #{target} HTTP/1.1"
          )
  end

  test "Phoenix answers the trips list for a signed-out visitor with Rails' sign-in redirect" do
    port = serve()

    for target <- ~w(/trips /trips?page=2) do
      assert answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302, target
    end
  end

  test "value-less browser query keys go to Puma unchanged while valued keys stay in Phoenix",
       ctx do
    port = serve()

    for target <- ~w(/trips?page /trips?view /stats?year) do
      assert answered_by_puma(port, ctx.upstream, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") ==
               "GET #{target} HTTP/1.1"
    end

    assert answered_by_phoenix(port, "GET /trips?page=2 HTTP/1.1\r\nHost: a\r\n\r\n") == 302
  end

  test "every other trip route, format and method goes to Puma", ctx do
    port = serve()

    for target <-
          ~w(/trips/new /trips/5/edit /trips/abc /trips/12abc /trips/1234567890123456789 /trips.json /trips/5.json /trips?format=json /trips/5/share_link/new) do
      assert answered_by_puma(port, ctx.upstream, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") ==
               "GET #{target} HTTP/1.1"
    end

    for {method, target} <- [
          {"POST", "/trips"},
          {"PATCH", "/trips/5"},
          {"PUT", "/trips/5"},
          {"DELETE", "/trips/5"},
          {"POST", "/trips/5/recalculate"},
          {"POST", "/trips/5/export?file_format=gpx"},
          {"POST", "/trips/5/notes"},
          {"PATCH", "/trips/5/notes/7"},
          {"DELETE", "/trips/5/notes/7"},
          {"POST", "/trips/5/share_link"},
          {"DELETE", "/trips/5/share_link"},
          {"PATCH", "/trips/5/share_link/revoke"},
          {"POST", "/trips/5/share_link/regenerate"},
          {"POST", "/trips/5/share_link/regenerate_phrase"}
        ] do
      body = "_method=delete&authenticity_token=x"

      request =
        "#{method} #{target} HTTP/1.1\r\nHost: a\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"

      assert answered_by_puma(port, ctx.upstream, request) == "#{method} #{target} HTTP/1.1"
    end
  end

  test "DAWARICH_RAILS_ROUTES=trips hands both pages back with their query", ctx do
    Application.put_env(:dawarich, :rails_routes, ["trips"])
    port = serve()

    for target <- ~w(/trips /trips?page=2 /trips/5) do
      assert answered_by_puma(port, ctx.upstream, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") ==
               "GET #{target} HTTP/1.1"
    end
  end

  test "Rails keeps guest achievement requests intact, including malformed page shapes and writes",
       ctx do
    port = serve()

    for target <-
          ~w(/achievements /achievements/country_de /achievements/unknown /achievements.json /achievements/country_de.json /achievements?format=json /achievements?unexpected=value /achievements?q[a]=value) do
      assert answered_by_puma(port, ctx.upstream, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") ==
               "GET #{target} HTTP/1.1"
    end

    for target <-
          ~w(/achievements/country_de/toggle_sharing /achievements/unlocks/next /achievements/unlocks/123/seen /achievements/unlocks/dismiss) do
      body = "authenticity_token=x"

      request =
        "POST #{target} HTTP/1.1\r\nHost: a\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"

      assert answered_by_puma(port, ctx.upstream, request) == "POST #{target} HTTP/1.1"
    end
  end

  test "DAWARICH_RAILS_ROUTES=sharing hands the shared-link page and its unlock back with their query",
       ctx do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    Dawarich.Test.SharingSeeds.load!()
    Dawarich.ScratchRepo.query!("TRUNCATE phoenix.counters", [], log: false)
    port = serve()
    id = "a9500000-0000-4000-8000-000000000001"
    page = "GET /s/#{id}?locale=de HTTP/1.1\r\nHost: a\r\n\r\n"

    unlock =
      "POST /s/#{id}/unlock HTTP/1.1\r\nHost: a\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
        "Content-Length: 8\r\n\r\nphrase=x"

    assert answered_by_phoenix(port, page) == 200
    assert answered_by_phoenix(port, unlock) == 401

    Application.put_env(:dawarich, :rails_routes, ["sharing"])
    on_exit(fn -> Application.delete_env(:dawarich, :rails_routes) end)

    assert answered_by_puma(port, ctx.upstream, page) == "GET /s/#{id}?locale=de HTTP/1.1"
    assert answered_by_puma(port, ctx.upstream, unlock) == "POST /s/#{id}/unlock HTTP/1.1"
  end

  test "Phoenix answers the settings, account and insights pages itself" do
    port = serve()

    for target <-
          ~w(/settings/general /settings/integrations /settings/integrations?service=trek /users/edit /insights /insights?year=all&month=3) do
      assert answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302, target
    end
  end

  test "every other settings, account and insights path, and every write, goes to Puma", ctx do
    port = serve()

    for target <-
          ~w(/settings /settings/theme?theme=light /settings/visits /settings/two_factor /settings/background_jobs /settings/users /settings/users/export /settings/trek_sources/1/select_trips /insights/details?year=2024 /users/sign_in /users/sign_up /users/edit.json /settings/general.json /insights.json),
        do:
          assert(
            answered_by_puma(port, ctx.upstream, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") ==
              "GET #{target} HTTP/1.1"
          )

    for {method, target} <- [
          {"PATCH", "/settings/general"},
          {"POST", "/settings/general/verify_supporter"},
          {"POST", "/settings/general/test_email"},
          {"PATCH", "/settings/integrations"},
          {"POST", "/settings/trek_sources"},
          {"DELETE", "/settings/trek_sources/1"},
          {"POST", "/settings/background_jobs?job_name=start_airtrail_import"},
          {"PATCH", "/settings/changelog_consent"},
          {"POST", "/settings/generate_api_key"},
          {"POST", "/settings/users/export"},
          {"POST", "/settings/users/import"},
          {"PUT", "/users"},
          {"DELETE", "/users"}
        ] do
      body = "authenticity_token=x"

      request =
        "#{method} #{target} HTTP/1.1\r\nHost: a\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"

      assert answered_by_puma(port, ctx.upstream, request) == "#{method} #{target} HTTP/1.1"
    end
  end

  test "DAWARICH_RAILS_ROUTES hands the settings, account and insights pages back", ctx do
    Application.put_env(:dawarich, :rails_routes, ["settings", "users", "insights"])
    port = serve()

    for target <-
          ~w(/settings/general /settings/integrations?service=immich /users/edit /insights?year=2024),
        do:
          assert(
            answered_by_puma(port, ctx.upstream, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") ==
              "GET #{target} HTTP/1.1"
          )
  end

  test "Phoenix answers both map paths itself", _ctx do
    port = serve()

    for target <- ~w(/map /map/v2 /map/v2?date=2026-09-29&panel=timeline),
        do: assert(answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302)
  end

  test "every other map path, method and format goes to Puma unchanged", ctx do
    port = serve()
    get = fn target, headers -> "GET #{target} HTTP/1.1\r\nHost: a\r\n#{headers}\r\n" end

    for {target, headers} <- [
          {"/maps/v2", ""},
          {"/map/v1", ""},
          {"/map/timeline_feeds?date=2026-09-29", ""},
          {"/api/v1/timeline?start_at=1&end_at=2", ""},
          {"/map/v2", "Accept: application/json\r\n"},
          {"/map/v2?format=json", ""},
          {"/map/v2", "X-Requested-With: XMLHttpRequest\r\n"}
        ],
        do:
          assert(
            answered_by_puma(port, ctx.upstream, get.(target, headers)) ==
              "GET #{target} HTTP/1.1"
          )

    body = "authenticity_token=x"

    for method <- ~w(POST PATCH DELETE) do
      request =
        "#{method} /map/v2 HTTP/1.1\r\nHost: a\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"

      assert answered_by_puma(port, ctx.upstream, request) == "#{method} /map/v2 HTTP/1.1"
    end
  end

  test "DAWARICH_RAILS_ROUTES=map hands both map paths back to Puma with their query", ctx do
    Application.put_env(:dawarich, :rails_routes, ["map"])
    on_exit(fn -> Application.delete_env(:dawarich, :rails_routes) end)
    port = serve()

    for target <- ~w(/map /map/v2?panel=timeline&date=2026-09-29),
        do:
          assert(
            answered_by_puma(port, ctx.upstream, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") ==
              "GET #{target} HTTP/1.1"
          )

    assert answered_by_phoenix(port, "GET /notifications HTTP/1.1\r\nHost: a\r\n\r\n") == 302
  end

  test "DAWARICH_RAILS_ROUTES=places hands the list and the drawer back with their query", ctx do
    Application.put_env(:dawarich, :rails_routes, ["places"])
    on_exit(fn -> Application.delete_env(:dawarich, :rails_routes) end)
    port = serve()
    frame = "Accept: text/html, application/xhtml+xml\r\nTurbo-Frame: place-drawer\r\n"

    for {target, headers} <- [{"/places", ""}, {"/places?page=2", ""}, {"/places/5", frame}],
        do:
          assert(
            answered_by_puma(
              port,
              ctx.upstream,
              "GET #{target} HTTP/1.1\r\nHost: a\r\n#{headers}\r\n"
            ) ==
              "GET #{target} HTTP/1.1"
          )
  end

  test "Phoenix answers the map frames itself" do
    port = serve()
    accept = "Accept: text/html, application/xhtml+xml\r\n"

    for target <- [
          "/map/timeline_feeds/5/track_info",
          "/map/timeline_feeds?start_at=2026-09-27T00:00:00&end_at=2026-09-27T23:59:59",
          "/map/timeline_feeds/calendar?month=2026-09",
          "/map/timeline_feeds/calendar",
          "/map/residency?year=2026",
          "/map/residency",
          "/tracks/5/segments"
        ],
        do:
          assert(
            answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n#{accept}\r\n") == 302
          )
  end

  test "frame inputs Phoenix does not reproduce go to Puma unchanged", ctx do
    port = serve()
    frame = "Accept: text/html, application/xhtml+xml\r\n"
    get = fn target, headers -> "GET #{target} HTTP/1.1\r\nHost: a\r\n#{headers}\r\n" end

    for {target, headers} <- [
          {"/map/timeline_feeds/abc/track_info", frame},
          {"/map/timeline_feeds/1234567890123456789/track_info", frame},
          {"/map/timeline_feeds/5/track_info?locale=de", frame},
          {"/map/timeline_feeds/5/track_info?client=ios", frame},
          {"/map/timeline_feeds/5/track_info?aff=a6s2", frame},
          {"/map/timeline_feeds/calendar?month=2026-09&via=a6s2", frame},
          {"/map/timeline_feeds/5/track_info", frame <> "X-Dawarich-Client: ios\r\n"},
          {"/map/timeline_feeds/5/track_info", "Accept: application/json\r\n"},
          {"/map/timeline_feeds/5/track_info", frame <> "X-Requested-With: XMLHttpRequest\r\n"},
          {"/map/timeline_feeds/5/track_info?format=json", frame},
          {"/map/timeline_feeds?date=2026-09-29", frame},
          {"/map/timeline_feeds?start_at=&end_at=2026-09-27T23:59:59", frame},
          {"/map/timeline_feeds?start_at=Oct%2015%202025&end_at=2026-09-27T23:59:59", frame},
          {"/map/timeline_feeds?start_at[]=1&end_at=2", frame},
          {"/map/timeline_feeds?start_at=1&end_at=2&locale=de", frame},
          {"/map/timeline_feeds/calendar?month=2026-9", frame},
          {"/map/residency?year=abc", frame},
          {"/map/residency?year=", frame},
          {"/map/residency?year=2040", frame},
          {"/tracks/5/segments?locale=de", frame}
        ],
        do:
          assert(
            answered_by_puma(port, ctx.upstream, get.(target, headers)) ==
              "GET #{target} HTTP/1.1"
          )
  end

  test "DAWARICH_RAILS_ROUTES=map hands the frames back with the page", ctx do
    Application.put_env(:dawarich, :rails_routes, ["map"])
    on_exit(fn -> Application.delete_env(:dawarich, :rails_routes) end)
    port = serve()

    for target <- [
          "/map/v2",
          "/map/timeline_feeds/5/track_info",
          "/map/timeline_feeds?start_at=2026-09-27T00:00:00&end_at=2026-09-27T23:59:59",
          "/map/timeline_feeds/calendar?month=2026-09",
          "/map/residency?year=2026"
        ],
        do:
          assert(
            answered_by_puma(port, ctx.upstream, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") ==
              "GET #{target} HTTP/1.1"
          )

    drawer =
      "GET /places/5 HTTP/1.1\r\nHost: a\r\nAccept: text/html, application/xhtml+xml\r\n" <>
        "Turbo-Frame: place-drawer\r\n\r\n"

    assert answered_by_phoenix(port, drawer) == 302
  end
end
