defmodule Dawarich.RailsCache.Connection do
  @moduledoc "A dedicated cache connection; cache DB differs from jobs Redis DB."
  def child_specs(config \\ Application.get_env(:dawarich, :rails_cache, [])) do
    case config[:url] do
      url when is_binary(url) and url != "" ->
        [Redix.child_spec({url, options(url, config[:database] || 0)})]

      _ ->
        []
    end
  end

  def command(args), do: Dawarich.Redis.command(args, __MODULE__)

  defp options(url, database),
    do: Dawarich.Redis.options(url, database) |> Keyword.put(:name, __MODULE__)
end
