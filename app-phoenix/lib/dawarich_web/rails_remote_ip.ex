defmodule DawarichWeb.RailsRemoteIp do
  @moduledoc false
  import Bitwise
  alias DawarichWeb.RackIp

  def ip(conn) do
    remote = conn.remote_ip |> :inet.ntoa() |> to_string()

    clients =
      conn |> Plug.Conn.get_req_header("client-ip") |> Enum.join(", ") |> split() |> valid()

    forwarded = conn |> RackIp.forwarded_for() |> List.wrap() |> valid()

    if clients != [] and forwarded != [] and hd(clients) not in forwarded,
      do: raise(ArgumentError, "IP spoofing attack")

    ips = Enum.reverse(forwarded) ++ Enum.reverse(clients)
    Enum.find(ips ++ [remote], &(not trusted?(&1))) || List.last(ips) || remote
  end

  defp split(value), do: String.split(String.trim(value), ~r/[,\s]+/, trim: true)

  defp valid(ips), do: Enum.filter(ips, &(is_binary(&1) and match?({:ok, _}, parse(&1))))

  defp parse(ip), do: :inet.parse_strict_address(String.to_charlist(ip))

  defp trusted?(ip) do
    case parse(ip) do
      {:ok, {127, _, _, _}} -> true
      {:ok, {10, _, _, _}} -> true
      {:ok, {172, b, _, _}} when b in 16..31 -> true
      {:ok, {192, 168, _, _}} -> true
      {:ok, {169, 254, _, _}} -> true
      {:ok, {0, 0, 0, 0, 0, 0, 0, 1}} -> true
      {:ok, {a, _, _, _, _, _, _, _}} when band(a, 0xFE00) == 0xFC00 -> true
      {:ok, {a, _, _, _, _, _, _, _}} when band(a, 0xFFC0) == 0xFE80 -> true
      _ -> false
    end
  end
end
