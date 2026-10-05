defmodule Dawarich.Imports.Trek.Endpoint do
  @moduledoc false
  alias Dawarich.Imports.Trek.Client.Error
  @always [{0x00000000, 8}, {0xA9FEA9FE, 32}, {0xE0000000, 4}, {0xF0000000, 4}]
  @cloud [
    {0x0A000000, 8},
    {0x64400000, 10},
    {0x7F000000, 8},
    {0xA9FE0000, 16},
    {0xAC100000, 12},
    {0xC0000000, 24},
    {0xC0A80000, 16},
    {0xC6120000, 15}
  ]
  @v6_always [
    {0xFE800000000000000000000000000000, 10},
    {0xFF000000000000000000000000000000, 8}
  ]
  @v6_cloud [{1, 128}, {0xFC000000000000000000000000000000, 7}]

  def resolve!(url, opts) do
    uri = URI.parse(url)

    unless uri.scheme in ["http", "https"],
      do: reject!(opts, "invalid_scheme", %{scheme: uri.scheme})

    if uri.host in [nil, ""], do: reject!(opts, "host_required")
    hosted = Keyword.get_lazy(opts, :self_hosted?, &Dawarich.ReleaseMigration.self_hosted?/0)
    if uri.userinfo && not hosted, do: reject!(opts, "embedded_credentials")
    host = uri.host |> String.trim_leading("[") |> String.trim_trailing("]")

    addresses =
      Enum.flat_map([:inet, :inet6], fn family ->
        case :inet.getaddrs(String.to_charlist(host), family) do
          {:ok, ips} -> ips
          _ -> []
        end
      end)
      |> Enum.uniq()

    if addresses == [], do: reject!(opts, "unresolvable_host", %{host: host})
    if Enum.any?(addresses, &blocked?(&1, hosted)), do: reject!(opts, "blocked_address")
    {%{uri | host: host}, hd(addresses)}
  rescue
    e in Error -> reraise e, __STACKTRACE__
    _ -> reject!(opts, "invalid_format")
  end

  def blocked?({a, b, c, d}, hosted),
    do:
      member?(
        a * 0x1000000 + b * 0x10000 + c * 0x100 + d,
        32,
        @always ++ if(hosted, do: [], else: @cloud)
      )

  def blocked?({0, 0, 0, 0, 0, 65535, g, h}, hosted), do: mapped?(g, h, hosted)
  def blocked?({0, 0, 0, 0, 0, 0, g, h}, hosted) when g * 65536 + h > 1, do: mapped?(g, h, hosted)

  def blocked?(tuple, hosted) when tuple_size(tuple) == 8 do
    value = tuple |> Tuple.to_list() |> Enum.reduce(0, &(&2 * 65536 + &1))
    member?(value, 128, @v6_always ++ if(hosted, do: [], else: @v6_cloud))
  end

  defp mapped?(g, h, hosted),
    do: blocked?({div(g, 256), rem(g, 256), div(h, 256), rem(h, 256)}, hosted)

  defp member?(value, width, ranges),
    do:
      Enum.any?(ranges, fn {base, bits} ->
        div(value, Integer.pow(2, width - bits)) == div(base, Integer.pow(2, width - bits))
      end)

  defp reject!(opts, key, values \\ %{}) do
    message =
      DawarichWeb.Translate.t(
        Keyword.get(opts, :locale, "en"),
        "services.concerns.url_validatable." <> key,
        values
      )

    raise Error, message: "TREK URL was rejected: " <> message
  end
end
