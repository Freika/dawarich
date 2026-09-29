defmodule DawarichWeb.PublicFilesTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log
  @moduletag :tmp_dir

  import Dawarich.Test.RawHTTP

  alias DawarichWeb.{Origin, PublicFiles}

  @fixture "test/fixtures/public_files.json" |> File.read!() |> Jason.decode!()
  @hop_by_hop ~w(connection keep-alive date)
  @proxied ~w(
    post options range range-multi dotdot dotdot-encoded dot-segment docs-dotdot double-slash
    inner-double-slash dotfile dotdir symlink symlink-escape symlink-dir nul bad-escape invalid-utf8
    backslash unknown-extension pdf missing only-gz-plain root dir-without-index host-blocked
    no-host forwarded-host-blocked forwarded-host-list-blocked ssl-http ssl-forwarded-http
  )

  defmodule Harness do
    @moduledoc false
    @behaviour Plug

    import Plug.Conn

    def init(opts), do: opts

    def call(conn, opts) do
      conn = DawarichWeb.PublicFiles.call(conn, opts)

      if conn.halted,
        do: conn,
        else: conn |> put_resp_header("x-test", "proxied") |> send_resp(418, "")
    end
  end

  setup %{tmp_dir: tmp_dir} do
    root = Path.join(tmp_dir, "public")

    for %{"path" => path, "content" => content, "mtime" => mtime} <- @fixture["tree"]["files"] do
      file = Path.join(root, path)
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, Base.decode64!(content))
      File.touch!(file, mtime)
    end

    for %{"path" => path, "target" => target} <- @fixture["tree"]["symlinks"],
        do: File.ln_s!(target, Path.join(root, path))

    %{root: root}
  end

  defp env(stack, rails_env \\ "production") do
    %{
      "RAILS_ENV" => rails_env,
      "APPLICATION_HOSTS" => @fixture["application_hosts"],
      "APPLICATION_PROTOCOL" => if(stack == "force_ssl", do: "https", else: "http")
    }
  end

  test "boot configuration memoizes the resolved Rails environment" do
    config = PublicFiles.boot_config()
    assert config.rails_env == Dawarich.RailsSecret.rails_env(config.env)
  end

  defp serve(plug) do
    options = [plug: plug] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)
    bandit = start_supervised!({Bandit, options}, id: make_ref())
    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    port
  end

  defp ask(port, %{"method" => method, "target" => target, "headers" => headers} = request) do
    socket = connect(port)
    lines = Enum.map(headers, fn [name, value] -> "#{name}: #{value}\r\n" end)
    request_line = "#{method} #{target} HTTP/#{request["version"]}\r\n"
    send_raw(socket, [request_line, lines, "Connection: close\r\n\r\n"])
    {status, headers, body} = read_response(socket, method: method)
    :gen_tcp.close(socket)

    %{
      "status" => status,
      "headers" =>
        headers
        |> Enum.reject(fn {name, _} -> name in @hop_by_hop end)
        |> Enum.map(&Tuple.to_list/1)
        |> Enum.sort(),
      "body" => Base.encode64(body)
    }
  end

  defp proxied?(answer), do: ["x-test", "proxied"] in answer["headers"]

  test "every file Rails serves from public/ comes from Phoenix byte for byte, or goes to Puma",
       %{root: root} do
    ports = Map.new(~w(plain force_ssl), &{&1, serve({Harness, root: root, env: env(&1)})})

    results =
      for request <- @fixture["requests"] do
        answer = ask(ports[request["stack"]], request)
        {request["name"], proxied?(answer), answer == request["response"]}
      end

    assert Enum.sort(for {name, true, _} <- results, do: name) == Enum.sort(@proxied)
    assert for({name, false, false} <- results, do: name) == []
  end

  test "Phoenix knows exactly the MIME types Rails' booted Rack::Mime gives the fixture's extensions" do
    rails = @fixture["rails_mime_types"]

    for {extension, type} <- PublicFiles.content_types() do
      assert Map.fetch(rails, extension) == {:ok, type}, extension
    end
  end

  test "a host Phoenix cannot match exactly as Rails does is left to Rails" do
    assert Origin.authorized_host?("localhost:3000", nil)
    refute Origin.authorized_host?("dawarich.example", "\u00a0dawarich.example")
    refute Origin.authorized_host?("dawarich.example", "")
    refute Origin.authorized_host?("", "dawarich.example, ,")
    refute Origin.authorized_host?("d\u00e5warich.example", "d\u00e5warich.example")
  end

  test "outside production and staging every file goes to Puma", %{root: root} do
    robots = Enum.find(@fixture["requests"], &(&1["name"] == "robots"))

    for {rails_env, served?} <- [{"staging", true}, {"development", false}, {"test", false}] do
      port = serve({Harness, root: root, env: env("plain", rails_env)})
      assert proxied?(ask(port, robots)) == not served?, rails_env
    end
  end

  test "leaves API requests to Puma even when a matching public file exists", %{root: root} do
    path = Path.join(root, "api/v1/health")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "static")

    conn =
      Plug.Test.conn(:get, "/api/v1/health")
      |> then(&%{&1 | req_headers: [{"host", "dawarich.example"}]})
      |> PublicFiles.call(root: root, env: env("plain"))

    refute conn.halted
  end

  test "serves from the boot configuration after the process cwd changes", %{
    root: root,
    tmp_dir: tmp_dir
  } do
    previous = Application.get_env(:dawarich, :public_files)
    previous_rails_env = System.get_env("RAILS_ENV")
    Application.put_env(:dawarich, :public_files, %{root: root, env: env("plain")})

    original_cwd = File.cwd!()

    on_exit(fn ->
      File.cd!(original_cwd)

      if previous,
        do: Application.put_env(:dawarich, :public_files, previous),
        else: Application.delete_env(:dawarich, :public_files)

      if previous_rails_env,
        do: System.put_env("RAILS_ENV", previous_rails_env),
        else: System.delete_env("RAILS_ENV")
    end)

    changed_cwd = Path.join(tmp_dir, "cwd")
    File.mkdir_p!(changed_cwd)
    File.cd!(changed_cwd)
    System.put_env("RAILS_ENV", "development")

    conn =
      Plug.Test.conn(:get, "/robots.txt")
      |> then(&%{&1 | req_headers: [{"host", "dawarich.example"}]})
      |> PublicFiles.call([])

    assert conn.status == 200
  end

  test "the endpoint serves public/ before the Strangler and leaves the rest to Puma", %{
    root: root
  } do
    upstream = listen()

    previous =
      Map.new(~w(RAILS_ENV APPLICATION_HOSTS APPLICATION_PROTOCOL), &{&1, System.get_env(&1)})

    previous_public_files = Application.get_env(:dawarich, :public_files)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    Application.put_env(:dawarich, :public_root, root)

    System.put_env(%{
      "RAILS_ENV" => "production",
      "APPLICATION_HOSTS" => "dawarich.example",
      "APPLICATION_PROTOCOL" => "http"
    })

    Application.put_env(:dawarich, :public_files, PublicFiles.boot_config())

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, nil)
      Application.delete_env(:dawarich, :public_root)

      if previous_public_files,
        do: Application.put_env(:dawarich, :public_files, previous_public_files),
        else: Application.delete_env(:dawarich, :public_files)

      Enum.each(previous, fn {name, value} ->
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end)
    end)

    port = serve(DawarichWeb.Endpoint)
    robots = Enum.find(@fixture["requests"], &(&1["name"] == "robots"))
    assert ask(port, robots) == robots["response"]

    for path <- ["/map", "/phoenix/js/phoenix.mjs.map"] do
      client = connect(port)
      send_raw(client, "GET #{path} HTTP/1.1\r\nHost: dawarich.example\r\n\r\n")
      puma = accept(upstream)
      {head, _} = read_head(puma)
      assert request_line(head) == "GET #{path} HTTP/1.1"
      reply(puma, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
      assert {404, _, ""} = read_response(client)
    end
  end
end
