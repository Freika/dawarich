defmodule Dawarich.Test.NativeQueryBudget do
  @moduledoc false
  def record(metadata, pid) do
    table =
      Enum.find(
        ~w(users notifications imports family_memberships tags instance_settings),
        &String.contains?(metadata.query, &1)
      ) || "other"

    send(pid, :query)
    send(pid, {:query_table, table})
  end

  def counts(values \\ %{}) do
    receive do
      {:query_table, table} -> counts(Map.update(values, table, 1, &(&1 + 1)))
    after
      0 -> values
    end
  end

  def classify(queries) do
    Enum.frequencies_by(queries, fn query ->
      Enum.find(
        ~w(users notifications imports family_memberships tags instance_settings),
        &String.contains?(query, &1)
      ) || "other"
    end)
  end
end
