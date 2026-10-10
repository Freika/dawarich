defmodule Dawarich.Settings.Map do
  @moduledoc false
  alias Dawarich.{Maps, Repo}
  alias Dawarich.Settings.{Api, Progress}

  def get(scope, opts \\ []) do
    Maps.with_actor(scope, fn actor ->
      {:ok, Api.config(Api.read(Repo, actor.id), Api.restricted?(Repo, actor, ctx(opts)))}
    end)
  end

  def update(scope, attrs, opts \\ []) when is_map(attrs) do
    Maps.with_actor(scope, fn actor ->
      case Api.update(Repo, actor, %{"settings" => attrs}, ctx(opts)) do
        {:ok, 200, body} ->
          {:ok,
           %{settings: body["settings"], recalculation_triggered: body["recalculation_triggered"]}}

        {:error, 423, _} ->
          {:error, :locked}

        {:error, 422, %{"errors" => errors}} ->
          {:error, {:invalid, errors}}

        {:error, status, _} when status in [400, 422] ->
          {:error, {:invalid, []}}

        {:error, status, _} when status in [401, 402] ->
          {:error, :unauthorized}

        _ ->
          {:error, :unavailable}
      end
    end)
  end

  def recalculation(scope, opts \\ []) do
    Maps.with_actor(scope, fn actor ->
      case Progress.show(actor, ctx(opts)) do
        {:ok, 200, status} -> {:ok, status}
        {:error, status, _} when status in [401, 402] -> {:error, :unauthorized}
        _ -> {:error, :unavailable}
      end
    end)
  end

  defp ctx(opts) do
    %{
      now: Keyword.get(opts, :now, DateTime.utc_now()),
      self_hosted?:
        Keyword.get_lazy(opts, :self_hosted?, &Dawarich.ReleaseMigration.self_hosted?/0)
    }
  end
end
