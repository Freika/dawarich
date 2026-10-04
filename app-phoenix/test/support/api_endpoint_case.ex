defmodule Dawarich.ApiEndpointCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  import Dawarich.Test.RawHTTP

  using do
    quote do
      use Dawarich.IngestCase, async: false
      import Dawarich.Test.RawHTTP
      import Dawarich.ApiEndpointCase
    end
  end

  @transport_env ~w(http_proxy https_proxy HTTP_PROXY HTTPS_PROXY SSL_CERT_FILE SSL_CERT_DIR)

  def clear_transport_env do
    saved = for name <- @transport_env, value = System.get_env(name), do: {name, value}
    Enum.each(@transport_env, &System.delete_env/1)

    ExUnit.Callbacks.on_exit(fn ->
      Enum.each(@transport_env, &System.delete_env/1)
      Enum.each(saved, fn {name, value} -> System.put_env(name, value) end)
    end)
  end

  def put_photo_source_timeout(milliseconds) do
    previous = Application.fetch_env(:dawarich, :photo_source_timeout)
    Application.put_env(:dawarich, :photo_source_timeout, milliseconds)

    ExUnit.Callbacks.on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:dawarich, :photo_source_timeout, value)
        :error -> Application.delete_env(:dawarich, :photo_source_timeout)
      end
    end)
  end

  def init(opts), do: opts

  def call(conn, opts) do
    conn
    |> Plug.Conn.assign(:api_now, opts[:api_now])
    |> Plug.Conn.assign(:api_repo, opts[:api_repo])
    |> DawarichWeb.Endpoint.call(DawarichWeb.Endpoint.init([]))
  end

  setup context do
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})

    plug =
      if context[:api_now],
        do: {__MODULE__, [api_now: context.api_now, api_repo: context[:api_repo]]},
        else: DawarichWeb.Endpoint

    bandit =
      start_supervised!({Bandit, [plug: plug] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)})

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    previous = System.get_env("TIME_ZONE")
    System.delete_env("TIME_ZONE")

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, nil)
      Enum.each(~w(SELF_HOSTED DAWARICH_RAILS_SLICES), &System.delete_env/1)
      if previous, do: System.put_env("TIME_ZONE", previous), else: System.delete_env("TIME_ZONE")
    end)

    clear_transport_env()
    %{port: port, upstream: upstream}
  end

  def request(port, target, headers, method \\ "GET") do
    client = connect(port)

    send_raw(client, [
      "#{method} #{target} HTTP/1.1\r\nHost: localhost\r\n",
      Enum.map(headers, fn {n, v} -> "#{n}: #{v}\r\n" end),
      "\r\n"
    ])

    client
  end

  def puma(upstream, body \\ "rails") do
    socket = accept(upstream)
    {head, _rest} = read_head(socket)
    reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: #{byte_size(body)}\r\n\r\n#{body}")
    request_line(head)
  end

  def no_upstream!(upstream), do: assert({:error, :timeout} = :gen_tcp.accept(upstream.listen, 0))

  def with_info_log(fun) do
    previous = Logger.level()
    Logger.configure(level: :info)

    try do
      ExUnit.CaptureLog.capture_log([level: :info], fun)
    after
      Logger.configure(level: previous)
    end
  end
end
