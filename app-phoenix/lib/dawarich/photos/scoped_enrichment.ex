defmodule Dawarich.Photos.ScopedEnrichment do
  @moduledoc false
  alias Dawarich.{Entitlements, Maps}
  alias Dawarich.Photos.Enrichment

  @scan ~w(start_date end_date tolerance)

  def scan(scope, params, opts \\ []) when is_map(params),
    do: run(scope, :scan, Map.take(params, @scan), opts)

  def enrich(scope, assets, opts \\ []) when is_list(assets),
    do: run(scope, :create, %{"assets" => assets}, opts)

  defp run(scope, action, params, opts) do
    Maps.with_actor(scope, fn actor ->
      now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
      hosted = Keyword.get_lazy(opts, :self_hosted?, &Dawarich.ReleaseMigration.self_hosted?/0)

      if Entitlements.full_access?(actor, hosted, now) do
        case Enrichment.run(action, actor, params, Keyword.take(opts, [:enqueue, :now])) do
          {:ok, 200, %{"error" => error}} when error not in [nil, ""] ->
            {:error, :provider_failed}

          {:ok, 200, result} ->
            {:ok, result}

          {:error, reason} when is_atom(reason) ->
            {:error, reason}

          _ ->
            {:error, :unavailable}
        end
      else
        {:error, :pro_required}
      end
    end)
  end
end
