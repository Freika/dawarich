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

  setup do
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})

    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    previous = System.get_env("TIME_ZONE")
    System.delete_env("TIME_ZONE")

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, nil)
      Enum.each(~w(SELF_HOSTED DAWARICH_RAILS_SLICES), &System.delete_env/1)
      if previous, do: System.put_env("TIME_ZONE", previous), else: System.delete_env("TIME_ZONE")
    end)

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
