defmodule Dawarich.Release.Lifecycle do
  @moduledoc false

  alias Dawarich.ReleaseMigration

  def mode(env \\ System.get_env()) do
    case Map.get(env, "DAWARICH_PHOENIX_LIFECYCLE", "false") do
      "false" -> {:ok, :rails}
      "true" -> native(env)
      _ -> {:error, :invalid_lifecycle_flag}
    end
  end

  defp native(env) do
    if ReleaseMigration.self_hosted?(env),
      do: {:ok, :native},
      else: {:error, :cloud_native_lifecycle}
  end
end
