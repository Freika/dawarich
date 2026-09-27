defmodule DawarichWeb.Origin do
  @moduledoc false

  def allowed?(uri), do: allowed?(uri, System.get_env("APPLICATION_HOSTS"))

  def allowed?(%URI{host: host}, application_hosts) when is_binary(host) do
    (application_hosts || "localhost")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.any?(&matches?(host, &1))
  end

  def allowed?(_uri, _application_hosts), do: false

  defp matches?(host, entry) do
    host = String.downcase(host)

    case entry |> strip_brackets() |> String.downcase() do
      "." <> domain -> Regex.match?(~r/\A(?:[a-z0-9-]+\.)?#{Regex.escape(domain)}\z/, host)
      plain -> host == plain
    end
  end

  defp strip_brackets("[" <> rest), do: String.trim_trailing(rest, "]")
  defp strip_brackets(entry), do: entry
end
