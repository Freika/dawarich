defmodule Dawarich.ReleaseMigrator.Ledger do
  @moduledoc false

  alias Dawarich.ReleaseMigrator.Floor

  @removed_versions ~w[20251228163703]
  @schema_rb_define_versions ~w[20241030152025 20250930150256]

  def removed_versions, do: @removed_versions

  def schema_rb_define_versions, do: @schema_rb_define_versions

  def classify(ledger, known) do
    cond do
      fresh?(ledger) -> :fresh
      count = not_dawarich(ledger) -> {:not_dawarich, count}
      release = below_floor(ledger) -> {:below_floor, release}
      true -> classify_supported(ledger, known)
    end
  end

  def not_dawarich(ledger) do
    if not fresh?(ledger) and MapSet.disjoint?(ledger, MapSet.new(Floor.versions())) do
      MapSet.size(ledger)
    end
  end

  def below_floor(ledger) do
    unless fresh?(ledger) or not_dawarich(ledger) do
      Enum.find_value(Floor.states(), fn {release, versions} ->
        unless Enum.all?(versions, &MapSet.member?(ledger, &1)), do: release
      end)
    end
  end

  defp fresh?(ledger), do: is_nil(ledger) or MapSet.size(ledger) == 0

  defp classify_supported(ledger, known) do
    known = MapSet.new(known)
    tolerated = MapSet.new(@removed_versions ++ @schema_rb_define_versions ++ Floor.versions())
    unknown = ledger |> MapSet.difference(known) |> MapSet.difference(tolerated)
    pending = known |> MapSet.difference(ledger) |> Enum.sort()

    cond do
      MapSet.size(unknown) > 0 -> {:newer, Enum.sort(unknown)}
      pending == [] -> :current
      true -> {:pending, pending}
    end
  end
end
