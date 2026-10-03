defmodule Dawarich.Auth.Recovery.Settings do
  @moduledoc false
  alias Dawarich.Auth.Account

  def sanitize(settings) when is_map(settings) do
    with {:ok, settings} <- trim_url(settings, "immich_url"),
         {:ok, settings} <- trim_url(settings, "photoprism_url") do
      strip_map_url(settings)
    end
  end

  def sanitize(settings), do: {:ok, settings}

  defp trim_url(settings, key) do
    case settings[key] do
      nil -> {:ok, settings}
      url when is_binary(url) -> {:ok, Map.put(settings, key, String.replace(url, ~r{/+\z}, ""))}
      _ -> :error
    end
  end

  defp strip_map_url(%{"maps" => maps} = settings) when is_map(maps) do
    case maps["url"] do
      nil ->
        {:ok, settings}

      url when is_binary(url) ->
        {:ok, put_in(settings, ["maps", "url"], Account.strip(url))}

      _ ->
        :error
    end
  end

  defp strip_map_url(%{"maps" => maps}) when is_list(maps) or is_integer(maps), do: :error
  defp strip_map_url(settings), do: {:ok, settings}
end
