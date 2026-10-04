defmodule Dawarich.Points.AnomalyBackfillProgress do
  @moduledoc false

  alias Dawarich.State

  def key(args), do: "anomaly_backfill:progress:" <> args["event_id"]

  def load(repo, args) do
    case State.cursor(repo, key(args)) do
      nil -> args["progress"] || %{}
      value -> Jason.decode!(value)
    end
  end

  def reset?(progress), do: "reset_flags" in Map.get(progress, "completed", [])
  def filtered?(progress), do: "filter_months" in Map.get(progress, "completed", [])

  def cursor(%{"current" => ["filter_months", value]}), do: value
  def cursor(_), do: 0

  def reset!(repo, args), do: save!(repo, args, %{"completed" => ["reset_flags"]})

  def month!(repo, args, first),
    do:
      save!(repo, args, %{"completed" => ["reset_flags"], "current" => ["filter_months", first]})

  def clear!(repo, args), do: State.delete_cursor(repo, key(args))

  def filtered!(repo, args),
    do: save!(repo, args, %{"completed" => ~w(reset_flags filter_months)})

  defp save!(repo, args, value), do: State.put_cursor(repo, key(args), Jason.encode!(value))
end
