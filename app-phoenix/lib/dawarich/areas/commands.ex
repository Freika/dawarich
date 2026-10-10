defmodule Dawarich.Areas.Commands do
  @moduledoc false
  alias Dawarich.{Maps, Repo}
  alias Dawarich.Areas.{Api, WebWrite}

  @fields ~w(name latitude longitude radius)

  def get(scope, id) do
    Maps.with_actor(scope, fn actor ->
      case Api.find(Repo, actor.id, id) do
        {:ok, area} -> {:ok, area}
        :not_found -> {:error, :not_found}
      end
    end)
  end

  def create(scope, attrs, opts \\ []) do
    Maps.with_actor(scope, fn actor ->
      Repo |> WebWrite.create(actor, cast(attrs), ctx(scope, opts)) |> saved(actor)
    end)
  end

  def update(scope, id, attrs, opts \\ []) do
    Maps.with_actor(scope, fn actor ->
      case Api.find(Repo, actor.id, id) do
        {:ok, %{"id" => area}} ->
          Repo |> WebWrite.update(actor, area, cast(attrs), ctx(scope, opts)) |> saved(actor)

        :not_found ->
          {:error, :not_found}
      end
    end)
  end

  def delete(scope, id, opts \\ []) do
    Maps.with_actor(scope, fn actor ->
      case Api.remove(Repo, actor, id, ctx(scope, opts)) do
        :ok -> :ok
        reason -> {:error, reason}
      end
    end)
  end

  defp cast(attrs) do
    for {key, value} <- attrs, key in @fields, is_binary(value), into: %{}, do: {key, value}
  end

  defp ctx(scope, opts),
    do: %{now: Keyword.get(opts, :now, DateTime.utc_now()), locale: scope.locale || "en"}

  defp saved({:ok, %{area: %{id: id}}}, actor) do
    {:ok, area} = Api.find(Repo, actor.id, id)
    {:ok, area}
  end

  defp saved({:invalid, errors}, _), do: {:error, {:invalid, errors}}
  defp saved(:not_found, _), do: {:error, :not_found}
  defp saved(:rails, _), do: {:error, :unavailable}
end
