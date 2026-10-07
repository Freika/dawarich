defmodule Dawarich.Standalone do
  @moduledoc false

  @obsolete ~w(DAWARICH_RAILS DAWARICH_PROXY DAWARICH_RAILS_ROUTES DAWARICH_RAILS_SLICES DAWARICH_RAILS_ARGS DAWARICH_PHOENIX_AUTH DAWARICH_OBAN_JOB_KEYS DAWARICH_PHOENIX_LIFECYCLE DAWARICH_BEHIND_PHOENIX DAWARICH_PHOENIX_NODE DAWARICH_CLOUD_DRAIN_ONLY)

  def validate_candidate_env!(env) do
    case Enum.find(@obsolete, &Map.has_key?(env, &1)) do
      nil ->
        :ok

      name ->
        raise ArgumentError,
              "#{name} is obsolete in the native candidate; remove it and use native commands"
    end
  end

  def enabled?(env \\ System.get_env()), do: env["DAWARICH_RAILS"] == "off"

  def job_entries(env \\ System.get_env()) do
    if enabled?(env),
      do: Dawarich.Jobs.Registry.entries(),
      else: Dawarich.Jobs.Claimer.entries(env["DAWARICH_OBAN_JOB_KEYS"])
  end
end
