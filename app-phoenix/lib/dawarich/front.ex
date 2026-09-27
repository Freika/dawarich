defmodule Dawarich.Front do
  @moduledoc false

  require Logger

  alias Dawarich.Front.{Command, Drainer}
  alias Dawarich.{RailsSecret, RailsServer}

  @off ~w(off false 0 no)
  @marker "DAWARICH_BEHIND_PHOENIX"
  @loopback_v6 {0, 0, 0, 0, 0, 0, 0, 1}

  def plan(argv, env, opts \\ [])

  def plan(nil, _env, _opts), do: :none

  def plan(argv, env, opts) do
    with :ok <- enabled(env),
         upstream = Keyword.get_lazy(opts, :upstream_port, &free_loopback_port/0),
         ipv6? = Keyword.get_lazy(opts, :ipv6?, &ipv6_available?/0),
         {:ok, public, puma_argv} <- Command.parse(argv, env, upstream, ipv6?),
         :ok <- bindable(public) do
      {:proxy, %{public: public, upstream: upstream, puma_argv: puma_argv}}
    else
      {:direct, cause} -> {:direct, argv, cause}
    end
  end

  def children(:none), do: [DawarichWeb.Endpoint]

  def children({:direct, argv, _cause}), do: [{RailsServer, argv: argv, env: [{@marker, false}]}]

  def children({:proxy, %{public: {ip, port}, puma_argv: puma_argv}}) do
    [
      {RailsServer, argv: puma_argv, env: [{@marker, "1"}]},
      {DawarichWeb.Endpoint,
       server: true,
       secret_key_base: RailsSecret.endpoint_secret(RailsSecret.fetch()),
       http: http_options(ip, port)}
      |> Supervisor.child_spec(shutdown: 5_000),
      {Drainer, []}
    ]
  end

  def upstream({:proxy, %{upstream: port}}), do: {"127.0.0.1", port}
  def upstream(_plan), do: nil

  def http_options(ip, port) do
    [
      ip: ip,
      port: port,
      startup_log: false,
      thousand_island_options: [
        shutdown_timeout: 5_000,
        transport_options: [reuseport: true] ++ family(ip)
      ],
      http_options: [compress: false],
      http_1_options: [
        max_request_line_length: 12_320,
        max_header_length: 82_180,
        max_header_count: 64
      ],
      http_2_options: [enabled: false],
      websocket_options: [compress: false]
    ]
  end

  def log(:none), do: :ok

  def log({:proxy, %{public: {ip, port}, upstream: upstream}}) do
    Logger.info(
      "Phoenix listens on #{address(ip)}:#{port} and proxies to Puma on 127.0.0.1:#{upstream}"
    )
  end

  def log({:direct, _argv, cause}) do
    Logger.warning("Phoenix proxy off (#{cause}); Puma serves the server command's own address")
  end

  def free_loopback_port(attempts \\ 50) do
    port = Enum.random(20_000..32_767)

    case :gen_tcp.listen(port, ip: {127, 0, 0, 1}) do
      {:ok, socket} ->
        :ok = :gen_tcp.close(socket)
        port

      {:error, _} when attempts > 1 ->
        free_loopback_port(attempts - 1)
    end
  end

  defp enabled(env) do
    value = env["DAWARICH_PROXY"] || ""
    if String.downcase(value) in @off, do: {:direct, "DAWARICH_PROXY=#{value}"}, else: :ok
  end

  defp bindable({ip, port}) do
    case :gen_tcp.listen(port, [:binary, ip: ip, reuseaddr: true, active: false] ++ family(ip)) do
      {:ok, socket} -> :gen_tcp.close(socket)
      {:error, reason} -> {:direct, "#{address(ip)}:#{port} is not available (#{reason})"}
    end
  end

  defp ipv6_available? do
    case :inet.getifaddrs() do
      {:ok, interfaces} ->
        Enum.any?(interfaces, fn {_name, opts} -> Enum.any?(opts, &ipv6_address?/1) end)

      _ ->
        false
    end
  end

  defp ipv6_address?({:addr, addr}) when tuple_size(addr) == 8, do: addr != @loopback_v6
  defp ipv6_address?(_), do: false

  defp family(ip) when tuple_size(ip) == 8, do: [:inet6]
  defp family(_ip), do: []

  defp address(ip) when tuple_size(ip) == 8, do: "[#{:inet.ntoa(ip)}]"
  defp address(ip), do: to_string(:inet.ntoa(ip))
end
