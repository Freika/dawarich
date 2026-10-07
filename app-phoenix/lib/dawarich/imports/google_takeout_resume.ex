defmodule Dawarich.Imports.GoogleTakeoutResume do
  @moduledoc false
  alias Dawarich.Imports.{BulkWriter, ContinuationReceipt, Fence, GpxProgress, NormalLifecycle}
  alias Dawarich.Imports.GoogleRecords.Point

  def validate(%{"locations" => locations, "current_index" => index} = payload)
      when is_list(locations) and is_integer(index) and index >= 0 and map_size(payload) == 2 do
    if Enum.all?(locations, &(is_map(&1) and not is_struct(&1))),
      do: {:ok, payload},
      else: {:error, "invalid_payload"}
  end

  def validate(_), do: {:error, "invalid_payload"}

  def call(lease, state, context, payload) do
    unless match?({:ok, _}, validate(payload)), do: raise(ArgumentError, "invalid_payload")
    digest = :crypto.hash(:sha256, Jason.encode!(payload)) |> Base.encode16(case: :lower)
    context = ContinuationReceipt.driver(lease, state, context, digest)

    context =
      Map.put(context, :altitude_decimal?, NormalLifecycle.altitude_decimal?(lease, context))

    offset = Map.get(context, :resume_offset, 0)

    payload["locations"]
    |> Enum.drop(offset)
    |> Enum.chunk_every(1000)
    |> Enum.reduce({offset, %{}, %{at: nil, index: nil}}, fn locations,
                                                             {index, cache, progress} ->
      batch = Enum.map(locations, &Point.prepare(&1, state.import, context))

      {_inserted, cache} =
        ContinuationReceipt.batch(context, index, length(locations), fn ->
          BulkWriter.write(batch, state.import, cache, lease.repo, &Fence.run(context, &1))
        end)

      progress = GpxProgress.record(state.import, payload["current_index"], progress, context)
      {index + length(locations), cache, progress}
    end)

    :ok
  end
end
