defmodule Dawarich.Jobs.Health do
  @moduledoc false

  @unknown %{"status" => "unknown", "alarm" => false}
  @key {__MODULE__, :summary}

  def summary(clock \\ &monotonic/0) do
    case :persistent_term.get(@key, nil) do
      {value, at} -> if clock.() - at > 60, do: @unknown, else: value
      nil -> @unknown
    end
  end

  def refresh(opts \\ []) do
    compute = Keyword.get(opts, :compute, fn -> compute(opts) end)
    clock = Keyword.get(opts, :clock, &monotonic/0)
    value = compute.()
    :persistent_term.put(@key, {value, clock.()})
    value
  end

  def reset, do: :persistent_term.erase(@key)

  defp compute(opts) do
    Dawarich.Admin.JobHealth.summary(
      Keyword.get(opts, :public_repo, Dawarich.Repo),
      Keyword.get(opts, :repo, Dawarich.Jobs.repo()),
      Keyword.get(opts, :node)
    )
  end

  defp monotonic, do: System.monotonic_time(:microsecond) / 1_000_000
end
