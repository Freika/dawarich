defmodule Dawarich.Integrations.Trek do
  @moduledoc false
  alias Dawarich.Accounts.Scope
  alias Dawarich.{Integrations, Repo}
  alias Dawarich.Imports.Trek.Sources

  def create_source(%Scope{user: user} = scope, params) do
    with :ok <- Integrations.authorize(scope),
         do: Sources.connect(Repo, user.id, params, options(scope))
  end

  def list_trips(scope, id, remote? \\ true) do
    with {:ok, source} <- available(scope, id),
         {:ok, trips} <- if(remote?, do: Sources.remote(source, options(scope)), else: {:ok, []}),
         do: {:ok, %{source: source, trips: trips, selected: Sources.selected(source)}}
  end

  def sync_source(scope, id) do
    with {:ok, source} <- available(scope, id), do: Sources.sync(source)
  end

  def delete_source(scope, id) do
    with {:ok, source} <- source(scope, id), do: Sources.disconnect(source)
  end

  def import_trips(scope, id, identifiers) do
    with {:ok, source} <- available(scope, id) do
      ids =
        identifiers
        |> List.wrap()
        |> Enum.map(&to_string/1)
        |> Enum.reject(&(String.trim(&1) == ""))
        |> Enum.uniq()

      if ids == [] do
        with {:ok, _} <- Sources.clear(source), do: {:ok, :empty}
      else
        with {:ok, trips} <- Sources.remote(source, options(scope)) do
          available =
            trips |> Enum.filter(&Sources.selectable?/1) |> Enum.map(&to_string(&1["id"]))

          ids = Enum.filter(ids, &(&1 in available))

          if ids == [] do
            {:error, :no_dated_trips}
          else
            with {:ok, _} <- Sources.select(source, ids), do: {:ok, :syncing}
          end
        end
      end
    end
  end

  defp source(%Scope{user: user} = scope, id) do
    with :ok <- Integrations.authorize(scope) do
      case Sources.get(Repo, user.id, id) do
        nil -> {:error, :not_found}
        source -> {:ok, source}
      end
    end
  end

  defp available(scope, id) do
    with {:ok, source} <- source(scope, id) do
      cond do
        source.status != 0 -> {:error, :disabled}
        source.importing -> {:error, :importing}
        true -> {:ok, source}
      end
    end
  end

  defp options(%Scope{locale: locale}),
    do: [self_hosted?: Integrations.self_hosted?(), locale: locale]
end
