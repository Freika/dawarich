defmodule Dawarich.VisitsApi.Closure do
  @moduledoc false
  alias Dawarich.{I18n, Jobs}
  alias Dawarich.VisitsApi.Batch

  def scope(action, user, params, now) do
    cutoff = Dawarich.MapApi.Closure.window(user, now)

    cond do
      cutoff == nil ->
        {:ok, params}

      action == :index ->
        {:ok, index_params(params, cutoff, user.timezone, now)}

      action in [:show, :update, :destroy, :possible_places, :select_place] ->
        id = Dawarich.RubyInteger.to_i(params["id"])
        if visible?(user.id, id, cutoff), do: {:ok, params}, else: :not_found

      action in [:merge, :bulk_update] and is_list(params["visit_ids"]) and
          params["visit_ids"] != [] ->
        ids = Enum.map(params["visit_ids"], &Dawarich.RubyInteger.to_i/1)
        allowed = Enum.filter(ids, &visible?(user.id, &1, cutoff))

        cond do
          action == :merge and length(allowed) != length(ids) ->
            {:error, 404, I18n.en!("controllers.api.v1.visits.one_or_more_visits_not_found")}

          action == :bulk_update and allowed == [] ->
            {:error, 422, I18n.en!("services.visits.bulk_update.none_found")}

          true ->
            {:ok, Map.put(params, "visit_ids", allowed)}
        end

      true ->
        {:ok, params}
    end
  end

  defp visible?(owner, id, cutoff) do
    Jobs.repo().query!(
      "SELECT EXISTS(SELECT 1 FROM visits WHERE user_id=$1 AND id=$2 AND started_at >= to_timestamp($3) AT TIME ZONE 'UTC' AND deleted_at IS NULL AND status!=2)",
      [owner, id, cutoff]
    ).rows == [[true]]
  end

  defp index_params(params, cutoff, zone, now) do
    if params["selection"] == "true" or
         (params["start_at"] not in [nil, ""] and params["end_at"] not in [nil, ""]) do
      from =
        if params["start_at"] in [nil, ""],
          do: cutoff,
          else: Dawarich.Imports.ImportTime.parse(params["start_at"], zone, now)

      if from do
        params
        |> Map.put("start_at", DateTime.to_iso8601(DateTime.from_unix!(max(from, cutoff))))
        |> Map.put("end_at", params["end_at"] || "9999-12-31T23:59:59Z")
      else
        params
      end
    else
      params
    end
  end

  def batch(owner, entries, zone, now) do
    if is_list(entries) and length(entries) in 1..100 do
      results =
        Enum.with_index(entries)
        |> Enum.map(fn {attrs, index} -> item(owner, attrs, index, zone, now) end)

      {:ok,
       %{
         results: results,
         created_count: Enum.count(results, &(&1.status == "created")),
         duplicate_count: Enum.count(results, &(&1.status == "duplicate")),
         failed_count: Enum.count(results, &(&1.status == "failed"))
       }}
    else
      Batch.call(owner, entries, zone, now)
    end
  end

  defp item(owner, attrs, index, zone, now) do
    case Batch.call(owner, [attrs], zone, now, Jobs.repo()) do
      {:ok, %{results: [row]}} -> Map.put(row, :index, index)
      _ -> failed(index)
    end
  rescue
    _ -> failed(index)
  end

  defp failed(index),
    do: %{
      index: index,
      status: "failed",
      error: I18n.en!("controllers.api.v1.visits.failed_to_create_visit")
    }
end
