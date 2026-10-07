defmodule Dawarich.Imports.GpxProgress do
  @moduledoc false
  require Logger
  alias Dawarich.Imports.{Fence, LeaseLost, Progress}

  def record(import, index, state, context) do
    now = clock(context.now)

    if index == 0 || is_nil(state.at) || DateTime.diff(now, state.at, :microsecond) >= 5_000_000 ||
         index - state.index >= 100 do
      Fence.run(context, fn ->
        value = if context[:continuation_progress?], do: "GREATEST(processed,$3)", else: "$3"

        context.repo.query!(
          "UPDATE imports SET processed=#{value} WHERE id=$1 AND user_id=$2 AND processed IS DISTINCT FROM #{value}",
          [import.id, import.user_id, index],
          log: false
        )
      end)

      publish(import, context)
      broadcast(import)
      %{at: now, index: index}
    else
      state
    end
  end

  defp publish(import, context) do
    Fence.run(context, fn ->
      Progress.publish!(context.repo, import, context.locale)
    end)
  rescue
    error in LeaseLost -> reraise error, __STACKTRACE__
    error -> Logger.warning("GPX progress transport failed: #{Exception.message(error)}")
  end

  defp broadcast(import) do
    Dawarich.Imports.Events.broadcast(import.user_id)
  rescue
    error -> Logger.warning("Native import progress failed: #{Exception.message(error)}")
  end

  defp clock(fun) when is_function(fun, 0), do: fun.()
  defp clock(now), do: now
end
