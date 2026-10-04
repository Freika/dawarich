defmodule Dawarich.Imports.NormalBatch do
  @moduledoc false
  alias Dawarich.Imports.{BulkWriter, Fence, LeaseLost, NormalBatchErrors}
  @limit 1000

  def new(import, context, policy) when policy in [:atomic, :non_atomic] do
    %{
      import: import,
      context: context,
      policy: policy,
      batch: [],
      size: 0,
      cache: %{},
      prepared: 0,
      inserted: 0
    }
  end

  def push(state, attrs) do
    state = %{state | batch: [attrs | state.batch], size: state.size + 1}
    if state.size == @limit, do: flush(state), else: state
  end

  def flush(%{size: 0} = state), do: state

  def flush(state) do
    {inserted, cache} = write(state)

    %{
      state
      | batch: [],
        size: 0,
        cache: cache,
        prepared: state.prepared + state.size,
        inserted: state.inserted + inserted
    }
  end

  def finish(state), do: flush(state)

  defp write(state) do
    BulkWriter.write(
      Enum.reverse(state.batch),
      state.import,
      state.cache,
      state.context.repo,
      fn fun -> Fence.run(state.context, fun) end
    )
  rescue
    error in LeaseLost ->
      reraise error, __STACKTRACE__

    error ->
      if state.policy == :atomic, do: reraise(error, __STACKTRACE__)
      NormalBatchErrors.notify!(state.import, state.context, error)
      {0, state.cache}
  end
end
