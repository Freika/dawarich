defmodule Dawarich.MapMatching.Atlas.ConnectionTest do
  require Logger
  alias Dawarich.MapMatching.Atlas.Client

  def call(url) when is_binary(url) do
    if String.trim(url) == "", do: {:error, "not_configured"}, else: check(url)
  end

  def call(nil), do: {:error, "not_configured"}

  defp check(url) do
    with {:ok, health} <- Client.health(url),
         {:ok, version} <- Client.version(url) do
      if health.routing == "up", do: {:ok, version}, else: {:error, "routing_unavailable"}
    else
      {:error, %Client.Error{} = error} ->
        Logger.warning(
          "event=atlas.connection_test_failed code=#{error.code} status=#{error.status}"
        )

        {:error, error.code}
    end
  end
end
