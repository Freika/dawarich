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

  def authorized_host?(host, application_hosts) do
    (application_hosts || "localhost")
    |> String.split(",")
    |> Enum.map(&ruby_strip/1)
    |> Enum.filter(&(&1 != "" and ascii?(&1)))
    |> Enum.any?(&Regex.match?(host_pattern(&1), host))
  end

  defp host_pattern("." <> domain),
    do: Regex.compile!("\\A(?:[a-z0-9-]+\\.)?#{Regex.escape(domain)}(?::\\d+)?\\z", "i")

  defp host_pattern(entry), do: Regex.compile!("\\A#{Regex.escape(entry)}(?::\\d+)?\\z", "i")

  defp ascii?(value), do: value =~ ~r/\A[\x20-\x7e]*\z/

  defp ruby_strip(value),
    do: String.replace(value, ~r/\A[\x00\t\n\x0b\f\r ]+|[\x00\t\n\x0b\f\r ]+\z/, "")

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
