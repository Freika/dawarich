defmodule Dawarich.Standalone do
  @moduledoc false

  def enabled?(env \\ System.get_env()), do: env["DAWARICH_RAILS"] == "off"

  def job_entries(env \\ System.get_env()) do
    if enabled?(env),
      do: Dawarich.Jobs.Registry.entries(),
      else: Dawarich.Jobs.Claimer.entries(env["DAWARICH_OBAN_JOB_KEYS"])
  end
end
