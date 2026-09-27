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

  defp matches?(host, "." <> domain), do: host == domain or String.ends_with?(host, "." <> domain)
  defp matches?(host, entry), do: host == entry
end
