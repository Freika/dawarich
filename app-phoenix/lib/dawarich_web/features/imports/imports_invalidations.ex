defmodule DawarichWeb.ImportsInvalidations do
  @moduledoc false
  def coalesce(owner), do: drain(owner, 100)
  defp drain(_, 0), do: :ok

  defp drain(owner, remaining) do
    receive do
      {:domain_changed, ^owner, :imports} -> drain(owner, remaining - 1)
    after
      0 -> :ok
    end
  end
end
