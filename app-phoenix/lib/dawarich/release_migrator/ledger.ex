defmodule Dawarich.ReleaseMigrator.Ledger do
  @moduledoc false

  alias Dawarich.ReleaseMigrator.Floor

  @removed_versions ~w[20251228163703]
  @prerelease_versions ~w[
    20250123145954 20250221121905 20250221125032 20250221144509 20250221151930
    20250913194134 20250914094851 20250914095157 20250928000001 20260310000004
    20260310000005 20260310000007 20260325163025 20260326152648 20260421000001
    20260508140000 20260508173900 20260508173923 20260831140000 20260901130000
  ]
  @schema_rb_define_versions ~w[20241030152025 20250930150256]

  def removed_versions, do: @removed_versions

  def prerelease_versions, do: @prerelease_versions

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

    tolerated =
      MapSet.new(
        @removed_versions ++
          @prerelease_versions ++ @schema_rb_define_versions ++ Floor.versions()
      )

    unknown = ledger |> MapSet.difference(known) |> MapSet.difference(tolerated)
    pending = known |> MapSet.difference(ledger) |> Enum.sort()

    cond do
      MapSet.size(unknown) > 0 -> {:newer, Enum.sort(unknown)}
      pending == [] -> :current
      true -> {:pending, pending}
    end
  end
end
