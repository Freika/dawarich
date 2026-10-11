defmodule Dawarich.LocationCommands.Points do
  @moduledoc false
  alias Dawarich.{Maps, Repo}
  alias Dawarich.Points.{ApiPosition, ApiWrites}

  def move(scope, id, params, opts \\ []) do
    Maps.with_actor(scope, fn actor ->
      Repo
      |> ApiPosition.update(actor, id, params, ctx(scope, opts))
      |> typed(fn {:object, fields} -> {:ok, Map.new(fields)} end)
    end)
  end

  def delete(scope, id, opts \\ []) do
    Maps.with_actor(scope, fn actor ->
      Repo |> ApiWrites.destroy(actor, id, ctx(scope, opts)) |> typed(fn _ -> :ok end)
    end)
  end

  def bulk_delete(scope, ids, opts \\ []) do
    Maps.with_actor(scope, fn actor ->
      Repo
      |> ApiWrites.bulk_destroy(actor, %{"point_ids" => ids}, ctx(scope, opts))
      |> typed(fn %{"count" => count} -> {:ok, count} end)
    end)
  end

  defp ctx(scope, opts) do
    %{
      now: Keyword.get(opts, :now, DateTime.utc_now()),
      self_hosted?:
        Keyword.get_lazy(opts, :self_hosted?, &Dawarich.ReleaseMigration.self_hosted?/0),
      locale: scope.locale || "en"
    }
  end

  defp typed({:ok, 200, body}, ok), do: ok.(body)
  defp typed({:error, 404, _}, _), do: {:error, :not_found}
  defp typed({:error, 409, {:object, fields}}, _), do: {:error, {:stale, Map.new(fields)}}
  defp typed({:error, 422, %{"error" => %{"code" => code}}}, _), do: {:error, {:invalid, code}}

  defp typed({:error, 422, %{"limit" => _}}, _),
    do: {:error, {:invalid, "too_many_points_selected"}}

  defp typed({:error, 422, _}, _), do: {:error, {:invalid, "no_points_selected"}}
  defp typed({:error, 403, _}, _), do: {:error, :forbidden}
  defp typed({:error, status, _}, _) when status in [401, 402], do: {:error, :unauthorized}
  defp typed(_, _), do: {:error, :unavailable}
end
