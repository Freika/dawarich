defmodule Dawarich.ReleaseMigrator.Ledger do
  @moduledoc false

  @removed_versions ~w[20251228163703]
  @schema_rb_define_versions ~w[20241030152025 20250930150256]

  def removed_versions, do: @removed_versions

  def schema_rb_define_versions, do: @schema_rb_define_versions

  def classify(nil, _known), do: :fresh

  def classify(%MapSet{} = ledger, known) do
    known = MapSet.new(known)
    tolerated = MapSet.new(@removed_versions ++ @schema_rb_define_versions)
    unknown = ledger |> MapSet.difference(known) |> MapSet.difference(tolerated)
    pending = known |> MapSet.difference(ledger) |> Enum.sort()

    cond do
      MapSet.size(unknown) > 0 -> {:newer, Enum.sort(unknown)}
      pending == [] -> :current
      true -> {:pending, pending}
    end
  end
end
