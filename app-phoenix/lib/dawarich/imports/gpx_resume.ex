defmodule Dawarich.Imports.GpxResume do
  @moduledoc false
  alias Dawarich.Imports.NormalResume

  def driver(lease, state, context),
    do: NormalResume.driver(lease, state, context, matches?: &matches?/2)

  def start!(lease, state, context), do: NormalResume.start!(lease, state, context)
  defp matches?(saved, state), do: saved["attachment"] == state.attachment
end
