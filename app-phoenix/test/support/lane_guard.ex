defmodule Dawarich.LaneGuard do
  @moduledoc false

  @lanes Module.concat(__MODULE__, Lanes)
  @violations Module.concat(__MODULE__, Violations)

  def attach! do
    :ets.new(@lanes, [:named_table, :public, :set, read_concurrency: true])
    :ets.new(@violations, [:named_table, :public, :bag, write_concurrency: true])

    :ok =
      :telemetry.attach(
        __MODULE__,
        [:dawarich, :scratch_repo, :query],
        &__MODULE__.handle_query/4,
        nil
      )
  end

  def guard!(lane) do
    test = self()
    :ets.insert(@lanes, {test, lane})
    ExUnit.Callbacks.on_exit(fn -> check!(test, lane) end)
    :ok
  end

  def handle_query(_event, _measurements, %{query: query}, _config) do
    for pid <- [self() | Process.get(:"$callers", [])], :ets.member(@lanes, pid) do
      :ets.insert(@violations, {pid, query})
    end
  end

  defp check!(test, lane) do
    :ets.delete(@lanes, test)

    case :ets.take(@violations, test) do
      [] ->
        :ok

      reached ->
        raise "a #{lane} test reached Dawarich.ScratchRepo, the :scratch_db lane's database: " <>
                inspect(Enum.map(reached, &elem(&1, 1)))
    end
  end
end
