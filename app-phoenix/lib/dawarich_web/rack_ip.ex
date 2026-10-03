defmodule DawarichWeb.RackIp do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2]

  alias Dawarich.ReleaseMigration
  alias DawarichWeb.RackScheme
  alias DawarichWeb.RailsProxy.Headers

  @octet "\\.(?:25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])"
  @trusted ~r/\A127(?:#{@octet}){3}\z|\A::1\z|(?i:\Af[cd][0-9a-f]{2}(?::[0-9a-f]{0,4}){0,7}\z)|\A10(?:#{@octet}){3}\z|\A172\.(?:1[6-9]|2[0-9]|3[01])(?:#{@octet}){2}\z|\A192\.168(?:#{@octet}){2}\z|(?i:\Alocalhost\z|\Aunix(?:\z|:))/
  @h "[0-9A-Fa-f]{1,4}"
  @hs "(?:#{@h}(?::#{@h})*)?"
  @v4 "\\d+\\.\\d+\\.\\d+\\.\\d+"
  @zone "%[-0-9A-Za-z._~]+"
  @ipv6 "(?:#{@h}:){7}#{@h}|#{@hs}::#{@hs}|(?:#{@h}:){6,6}#{@v4}|#{@hs}::(?:#{@h}:)*#{@v4}|[Ff][Ee]80(?::#{@h}){7}#{@zone}|[Ff][Ee]80:(?:#{@hs}::#{@hs}|:#{@hs})?:#{@h}#{@zone}"
  @bracketed ~r/\A\[(#{@ipv6})\](?::\d+)?\z/
  @plain ~r/\A([-a-zA-Z0-9._~%!$&'()*+,;=]*?)(?::\d+)?\z/

  def ip(conn) do
    remote = split(Headers.peer(conn.remote_ip))

    case remote |> Enum.reverse() |> Enum.find(&(not trusted?(&1))) do
      nil -> forwarded(forwarded_for(conn), remote)
      ip -> ip
    end
  end

  defp forwarded([_ | _] = list, _remote) do
    case list |> Enum.reverse() |> Enum.find(:all_trusted, &(not trusted?(&1))) do
      :all_trusted -> hd(list)
      ip -> ip
    end
  end

  defp forwarded(_list, remote), do: List.first(remote)

  defp forwarded_for(conn) do
    case RackScheme.forwarded_values(header(conn, "forwarded")) do
      %{"for" => values} ->
        Enum.map(values, &address/1)

      _ ->
        with value when is_binary(value) <- header(conn, "x-forwarded-for"),
             do: value |> split() |> Enum.map(&(&1 |> wrap() |> address()))
    end
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

  defp split(nil), do: []

  defp split(value) do
    value
    |> ReleaseMigration.ruby_strip()
    |> String.split(~r/[, \t]+/)
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
  end

  defp trusted?(nil), do: false
  defp trusted?(ip), do: Regex.match?(@trusted, ip)

  defp header(conn, name) do
    case get_req_header(conn, name) do
      [] -> nil
      values -> Enum.join(values, ", ")
    end
  end
end
