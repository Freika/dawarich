defmodule DawarichWeb.RailsRemoteIp do
  @moduledoc false
  defmodule IpSpoofAttackError do
    defexception message: "IP spoofing attack"
  end

  import Bitwise
  alias DawarichWeb.RailsProxy.Headers

  @trusted ~w(127.0.0.0/8 ::1/128 fc00::/7 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 fe80::/10)
  @h "[0-9A-Fa-f]{1,4}"
  @hs "(?:#{@h}(?::#{@h})*)?"
  @v4 "\\d+\\.\\d+\\.\\d+\\.\\d+"
  @zone "%[-0-9A-Za-z._~]+"
  @ipv6 "(?:#{@h}:){7}#{@h}|#{@hs}::#{@hs}|(?:#{@h}:){6,6}#{@v4}|#{@hs}::(?:#{@h}:)*#{@v4}|[Ff][Ee]80(?::#{@h}){7}#{@zone}|[Ff][Ee]80:(?:#{@hs}::#{@hs}|:#{@hs})?:#{@h}#{@zone}"
  @bracketed ~r/\A\[(#{@ipv6})\](?::\d+)?\z/
  @plain ~r/\A([-a-zA-Z0-9._~%!$&'()*+,;=]*?)(?::\d+)?\z/

  def ip(conn) do
    remote = Headers.peer(conn.remote_ip)

    clients =
      conn |> Plug.Conn.get_req_header("client-ip") |> Enum.join(", ") |> split() |> valid()

    forwarded =
      conn
      |> Plug.Conn.get_req_header("x-forwarded-for")
      |> Enum.join(", ")
      |> split()
      |> Enum.map(&(&1 |> wrap() |> address()))
      |> valid()

    if clients != [] and forwarded != [] and hd(clients) not in forwarded,
      do: raise(IpSpoofAttackError)

    ips = Enum.reverse(forwarded) ++ Enum.reverse(clients)
    Enum.find(ips ++ [remote], &(not trusted?(&1))) || List.last(ips) || remote
  end

  defp split(value), do: String.split(String.trim(value), ~r/[,\s]+/, trim: true)

  defp valid(ips), do: Enum.filter(ips, &(is_binary(&1) and match?({:ok, _}, parse(&1))))

  defp parse(ip), do: :inet.parse_strict_address(String.to_charlist(ip))

  defp trusted?(ip) do
    configured = Application.get_env(:dawarich, :trusted_proxies)
    proxies = if configured in [nil, []], do: @trusted, else: configured
    Enum.any?(proxies, &within?(ip, &1))
  end

  defp within?(ip, cidr) do
    [network | prefix] = String.split(cidr, "/", parts: 2)
    {:ok, network} = parse(network)
    {:ok, address} = parse(ip)
    bits = tuple_size(network) * if(tuple_size(network) == 4, do: 8, else: 16)
    prefix = if prefix == [], do: bits, else: String.to_integer(hd(prefix))
    if prefix < 0 or prefix > bits, do: raise(ArgumentError, "invalid trusted proxy prefix")

    tuple_size(network) == tuple_size(address) and
      bsr(number(network), bits - prefix) == bsr(number(address), bits - prefix)
  end

  defp number(ip) do
    width = if tuple_size(ip) == 4, do: 8, else: 16
    ip |> Tuple.to_list() |> Enum.reduce(0, &(bsl(&2, width) + &1))
  end

  defp address(authority) do
    case Regex.run(@bracketed, authority) || Regex.run(@plain, authority) do
      [_, address | _] -> address
      _ -> nil
    end
  end

  defp wrap(host) do
    if not String.starts_with?(host, "[") and length(String.split(host, ":")) > 2,
      do: "[" <> host <> "]",
      else: host
  end
end
