defmodule Dawarich.Jobs.Registry do
  @moduledoc false

  @entries []

  def entries, do: @entries

  def claimable, do: Enum.filter(@entries, & &1.claimable)

  def crontab,
    do:
      for(
        %{kind: :cron, expression: expression, worker: worker} <- @entries,
        do: {expression, worker}
      )

  def command(type) do
    case Enum.find(@entries, &(&1.key == "command:" <> type)) do
      %{kind: :command, worker: worker} -> {:ok, worker}
      _ -> :error
    end
  end
end
