defmodule Dawarich.Release.Lifecycle do
  @moduledoc false

  alias Dawarich.ReleaseMigration

  def mode(env \\ System.get_env())

  def mode(%{"DAWARICH_RAILS" => "off"} = env) do
    if ReleaseMigration.self_hosted?(env) or not cloud_configured?(env),
      do: native(env),
      else: flagged_mode(env)
  end

  def mode(env), do: flagged_mode(env)

  def admitted?(env \\ System.get_env()), do: mode(env) in [{:ok, :native}, {:ok, :rails}]

  defp flagged_mode(env) do
    case Map.get(env, "DAWARICH_PHOENIX_LIFECYCLE", "false") do
      flag when flag in ["false", "true"] ->
        if flag == "true" or env["DAWARICH_RAILS"] == "off",
          do: native(env),
          else: {:ok, :rails}

      _ ->
        {:error, :invalid_lifecycle_flag}
    end
  end

  defp native(env) do
    cond do
      ReleaseMigration.self_hosted?(env) -> {:ok, :native}
      cloud_configured?(env) -> {:ok, :native}
      true -> {:error, :cloud_native_lifecycle}
    end
  end

  defp cloud_configured?(env) do
    env["SELF_HOSTED"] == "false" and
      env["DAWARICH_CLOUD_DRAIN_ONLY"] in [nil, "false"] and
      Dawarich.Cloud.Configuration.manager(env) == :ok and
      Dawarich.Cloud.EndpointURL.session?(env["DATABASE_SESSION_URL"], env)
  end
end
