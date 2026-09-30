defmodule Dawarich.TimeZoneOptions do
  @moduledoc false

  require Logger

  def list do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        tap(
          load(Dawarich.RailsRoot.join("tmp/phoenix/time_zones.json")),
          &:persistent_term.put(__MODULE__, &1)
        )

      options ->
        options
    end
  end

  def read(path) do
    with {:ok, json} <- File.read(path),
         {:ok, %{"options" => options}} when is_list(options) <- Jason.decode(json) do
      for [label, iana] <- options, do: {label, iana}
    else
      _ -> []
    end
  end

  defp load(path) do
    case read(path) do
      [] ->
        Logger.warning("#{path} is missing or empty; run bin/rails phoenix:time_zones")
        []

      options ->
        options
    end
  end
end
