defmodule Dawarich.QrCache do
  @moduledoc false

  @max 1_000

  def create_table,
    do: :ets.new(__MODULE__, [:named_table, :public, :set, read_concurrency: true])

  def fetch(payload, fun) do
    key = :crypto.hash(:sha256, payload)

    case :ets.lookup(__MODULE__, key) do
      [{^key, value}] -> value
      [] -> store(key, fun.())
    end
  end

  defp store(key, value) do
    if :ets.info(__MODULE__, :size) >= @max, do: :ets.delete_all_objects(__MODULE__)
    :ets.insert(__MODULE__, {key, value})
    value
  end
end
