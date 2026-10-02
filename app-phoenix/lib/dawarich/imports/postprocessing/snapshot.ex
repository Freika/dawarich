defmodule Dawarich.Imports.Postprocessing.Snapshot do
  @moduledoc false
  alias Dawarich.Imports.Lease

  def effect!(lease, fun),
    do: Map.get(lease, :fence, fn effect -> Lease.effect!(lease, effect) end).(fun)

  def import!(lease, id) do
    effect!(lease, fn ->
      [[name, source, raw, doubles, points, status, data]] =
        lease.repo.query!(
          "SELECT name,source,raw_points,doubles,raw_data,additional_data_extraction_status,additional_data_extraction FROM imports WHERE id=$1",
          [id],
          log: false
        ).rows

      %{
        id: id,
        user_id: lease.import.user_id,
        name: name,
        source: source,
        raw_points: raw,
        doubles: doubles,
        raw_data: points,
        additional_data_extraction_status: status,
        additional_data_extraction: data
      }
    end)
  end

  def summary!(lease, id) do
    effect!(lease, fn ->
      [[count, first, last]] =
        lease.repo.query!(
          "SELECT count(*),min(timestamp),max(timestamp) FROM points WHERE import_id=$1",
          [id],
          log: false
        ).rows

      %{count: count, first: first, last: last}
    end)
  end

  def clock(%{now: fun}) when is_function(fun, 0), do: fun.()
  def clock(%{now: now}), do: now
  def naive(context), do: context |> clock() |> DateTime.to_naive()
end
