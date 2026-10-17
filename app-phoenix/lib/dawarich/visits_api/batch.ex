defmodule Dawarich.VisitsApi.Batch do
  @moduledoc false

  require Logger

  alias Dawarich.{I18n, Jobs}
  alias Dawarich.VisitsApi.{Create, Read}

  def call(owner, entries, zone, now, repo \\ Jobs.repo()) do
    cond do
      !is_list(entries) || entries == [] ->
        error("no_visits_provided")

      length(entries) > 100 ->
        {:ok, message} =
          I18n.t("en", "controllers.api.v1.visits.too_many_visits_maximum_is_limit_per_batch", %{
            "limit" => 100
          })

        {:error, 422, message, %{"limit" => 100, "requested" => length(entries)}}

      true ->
        with :ok <- admit(entries) do
          results =
            entries
            |> Enum.with_index()
            |> Enum.map(fn {attrs, index} -> item(repo, owner, attrs, index, zone, now) end)

          failed = Enum.count(results, &(&1.status == "failed"))

          if failed > 0,
            do: Logger.warning("Visits batch rejected #{failed} of #{length(entries)} entries")

          {:ok,
           %{
             results: results,
             created_count: Enum.count(results, &(&1.status == "created")),
             duplicate_count: Enum.count(results, &(&1.status == "duplicate")),
             failed_count: failed
           }}
        end
    end
  end

  defp admit(entries) do
    Enum.reduce_while(entries, :ok, fn attrs, :ok ->
      case if(is_map(attrs), do: Create.admit(attrs), else: :ok) do
        :ok -> {:cont, :ok}
        replay -> {:halt, replay}
      end
    end)
  end

  defp item(repo, owner, attrs, index, zone, now) when is_map(attrs) do
    case Create.call(
           owner,
           Map.take(attrs, ~w(name status latitude longitude started_at ended_at)),
           zone,
           now,
           repo
         ) do
      {:ok, visit} ->
        result = %{index: index, status: if(visit.duplicate, do: "duplicate", else: "created")}

        if visit.deleted_at do
          result
        else
          {:ok, payload} = Read.show(owner, visit.id, zone, repo, false)
          Map.put(result, :visit, payload)
        end

      {:error, 422, message} ->
        %{index: index, status: "failed", error: message}
    end
  rescue
    error in Postgrex.Error ->
      %{
        index: index,
        status: "failed",
        error: "Failed to create visit: " <> Exception.message(error)
      }
  end

  defp item(_repo, _owner, _attrs, index, _zone, _now),
    do: %{
      index: index,
      status: "failed",
      error: I18n.en!("controllers.api.v1.visits.invalid_visit_payload")
    }

  defp error(key), do: {:error, 422, I18n.en!("controllers.api.v1.visits." <> key)}
end
